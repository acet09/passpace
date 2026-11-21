package com.passpace.service;

import com.passpace.client.ReviewPageFetcher;
import com.passpace.crawler.AuthorHasher;
import com.passpace.crawler.ReviewSite;
import com.passpace.crawler.SourcePermissions;
import com.passpace.crawler.SourcePermissions.Permission;
import com.passpace.dto.collect.CollectDtos.FetchedPage;
import com.passpace.error.exception.CollectException;
import com.passpace.repository.JdbcReviewSubjectMentionRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * [용성 · 11-16] 이미 저장한 후기의 과목 언급 채우기 (관리자 버튼).
 *
 * 왜 필요한가: 크롤링은 이미 저장한 주소를 건너뛰므로, 새 추출기(SubjectStudyExtractor)를 넣기 전에 모은
 * 후기는 과목 정보가 비어 있다. 이 기능은 저장된 주소로 본문을 다시 읽어 <b>과목 언급만</b> 저장한다.
 *  - PASS_REVIEWS 는 읽기만 한다 (값을 바꾸지 않음)
 *  - velog·티스토리 글만 (네이버 요약문 출처는 본문을 읽지 않으므로 대상·남은 양에서 처음부터 뺀다)
 *  - 요청 간격·403·429 처리·재시도는 ReviewPageFetcher 규칙 그대로. 403·429 를 받으면 이번 실행을 멈춘다
 *  - 본문은 메모리에서만 쓰고, 전재 금지 글은 건너뛴다
 *  - 과목 언급이 하나도 없던 후기는 서버가 켜져 있는 동안 다시 읽지 않는다 (재시작하면 다시 확인)
 *  - 한 번에 limit 건만 처리한다 (응답을 기다리는 동안 화면이 멈추지 않도록 작게)
 *  - [11-19] 끝까지 자동(startAuto): 서버가 뒤에서 200건씩 이어서 돌린다. 403·429, 남은 후기 0건,
 *    더 줄지 않을 때, 관리자가 멈추기(stopAuto)를 누를 때 멈춘다. 자동 실행 중에는 수동 실행을 받지 않는다
 */
@Service
public class SubjectMentionBackfillService {

    private static final Logger log = LoggerFactory.getLogger(SubjectMentionBackfillService.class);
    public static final int MAX_LIMIT = 200;

    public record Result(String message, int target, int fetched, int reviewsWithMentions, int savedRows,
                         int skipped, int failed, String stoppedBy, List<String> samples) { }

    private final JdbcTemplate jdbc;
    private final ReviewPageFetcher fetcher;
    private final SourcePermissions permissions;
    private final AuthorHasher authorHasher;
    private final JdbcReviewSubjectMentionRepository mentions;
    private final SubjectStudyExtractor extractor = new SubjectStudyExtractor();

    private final Set<Long> checkedEmpty = ConcurrentHashMap.newKeySet();
    private final AtomicBoolean running = new AtomicBoolean(false);
    /** [11-19] 끝까지 자동 */
    private final AtomicBoolean autoRunning = new AtomicBoolean(false);
    private final AtomicBoolean stopRequested = new AtomicBoolean(false);
    private volatile int autoRounds;
    private volatile String autoMessage;

    /** 진행 상황 (관리자 화면이 2초마다 읽음) */
    public record Status(boolean tableReady, boolean running, int done, int target, int reviewsWithMentions,
                         int savedRows, int remaining, int checkedThisServerRun, String current,
                         boolean autoRunning, int autoRounds, String autoMessage) { }
    private volatile int progDone, progTarget, progWith, progSaved;
    private volatile String progUrl;

    public SubjectMentionBackfillService(JdbcTemplate jdbc, ReviewPageFetcher fetcher, SourcePermissions permissions,
                                         AuthorHasher authorHasher, JdbcReviewSubjectMentionRepository mentions) {
        this.jdbc = jdbc;
        this.fetcher = fetcher;
        this.permissions = permissions;
        this.authorHasher = authorHasher;
        this.mentions = mentions;
    }

    private record Row(long reviewId, String url, long certId, Integer dailyMinutes, BigDecimal totalHours) { }

    /** 수동 실행 (관리자 버튼). 끝까지 자동이 도는 중이면 받지 않는다 */
    public Result run(int limit) {
        if (autoRunning.get()) {
            return new Result("끝까지 자동 채우기가 실행 중입니다. 멈추기를 누르거나 끝난 뒤 다시 누르세요.",
                    0, 0, 0, 0, 0, 0, null, List.of());
        }
        return runBatch(limit);
    }

    /**
     * [11-19] 끝까지 자동 시작. 바로 돌아오고, 실제 처리는 뒤에서 한다 (진행은 status 로 확인).
     */
    public String startAuto() {
        if (!mentions.tableExists()) {
            return "REVIEW_SUBJECT_MENTIONS 테이블이 없습니다. db/10_review_subject_mentions.sql 을 먼저 실행하세요.";
        }
        if (running.get() || !autoRunning.compareAndSet(false, true)) {
            return "이미 실행 중입니다. 끝난 뒤 다시 누르세요.";
        }
        stopRequested.set(false);
        autoRounds = 0;
        autoMessage = "시작했습니다";
        Thread t = new Thread(this::autoLoop, "subject-backfill-auto");
        t.setDaemon(true);
        t.start();
        return "끝까지 자동 채우기를 시작했습니다. 200건씩 이어서 처리하며, 진행 상황은 상태 새로고침으로 확인하세요.";
    }

    /** [11-19] 끝까지 자동 멈추기: 지금 읽는 글까지만 처리하고 멈춘다 */
    public String stopAuto() {
        if (!autoRunning.get()) return "끝까지 자동 채우기가 실행 중이 아닙니다.";
        stopRequested.set(true);
        return "멈추기를 요청했습니다. 지금 읽는 글까지 처리하고 멈춥니다.";
    }

    private void autoLoop() {
        try {
            int before = remaining();
            while (!stopRequested.get()) {
                Result r = runBatch(MAX_LIMIT);
                autoRounds++;
                autoMessage = autoRounds + "회차 · " + r.message();
                if (r.stoppedBy() != null) {
                    autoMessage += " · " + r.stoppedBy();
                    break;
                }
                int after = remaining();
                if (r.target() == 0 || after == 0) {
                    autoMessage = "완료 · " + autoMessage;
                    break;
                }
                if (after >= before) {   // 권한 문제 등으로 같은 글만 다시 뽑히면 무한 반복하지 않게
                    autoMessage = "남은 후기가 더 줄지 않아 멈췄습니다 · " + autoMessage;
                    break;
                }
                before = after;
            }
            if (stopRequested.get()) autoMessage = "관리자가 멈춤 · " + autoMessage;
            log.info("과목 언급 끝까지 자동 종료: {}", autoMessage);
        } catch (RuntimeException e) {
            autoMessage = "오류로 멈췄습니다: " + e.getMessage();
            log.warn("과목 언급 끝까지 자동 오류", e);
        } finally {
            autoRunning.set(false);
        }
    }

    private Result runBatch(int limit) {
        int n = Math.max(1, Math.min(limit, MAX_LIMIT));
        if (!mentions.tableExists()) {
            return new Result("REVIEW_SUBJECT_MENTIONS 테이블이 없습니다. db/10_review_subject_mentions.sql 을 먼저 실행하세요.",
                    0, 0, 0, 0, 0, 0, null, List.of());
        }
        if (!running.compareAndSet(false, true)) {
            return new Result("이미 실행 중입니다. 끝난 뒤 다시 누르세요.", 0, 0, 0, 0, 0, 0, null, List.of());
        }
        try {
            List<Row> rows = targets(n);
            progDone = 0; progTarget = rows.size(); progWith = 0; progSaved = 0; progUrl = null;
            int fetched = 0, withMentions = 0, saved = 0, skipped = 0, failed = 0;
            String stoppedBy = null;
            List<String> samples = new ArrayList<>();
            Map<ReviewSite, Permission> perms = new EnumMap<>(ReviewSite.class);

            for (Row r : rows) {
                if (autoRunning.get() && stopRequested.get()) {   // [11-19] 멈추기를 누르면 다음 글부터 읽지 않음
                    break;
                }
                progUrl = r.url();
                progDone++;
                Optional<ReviewSite> site = ReviewSite.of(r.url());
                if (site.isEmpty()) {          // 네이버 등 본문을 읽지 않는 출처
                    skipped++;
                    checkedEmpty.add(r.reviewId());
                    continue;
                }
                Permission p = perms.computeIfAbsent(site.get(), permissions::check);
                if (!p.allowed()) {
                    skipped++;
                    continue;
                }
                try {
                    FetchedPage page = fetcher.fetchPost(r.url(), site.get(), authorHasher);
                    fetched++;
                    if (page.noReprint()) {
                        skipped++;
                        checkedEmpty.add(r.reviewId());
                        continue;
                    }
                    List<SubjectStudyExtractor.Mention> found = extractor.extract(
                            (page.title() == null ? "" : page.title()) + "\n" + page.text(),
                            r.dailyMinutes(), r.totalHours());
                    if (found.isEmpty()) {
                        checkedEmpty.add(r.reviewId());
                        continue;
                    }
                    int s = mentions.saveForReview(r.reviewId(), r.certId(), found);
                    if (s == 0) {
                        // 뽑은 과목이 모두 그 후기 자격증의 과목이 아니라 버려진 경우 (예: SQLD 후기의 "데이터베이스")
                        // → 표시해 두지 않으면 다음 실행에도 맨 앞에 다시 뽑혀 같은 글을 계속 읽는다
                        checkedEmpty.add(r.reviewId());
                        continue;
                    }
                    saved += s;
                    withMentions++;
                    progSaved = saved;
                    progWith = withMentions;
                    if (samples.size() < 15) {
                        found.forEach(m -> { if (samples.size() < 15) samples.add(m.type() + " · " + m.evidence() + " · " + r.url()); });
                    }
                } catch (CollectException e) {
                    failed++;
                    checkedEmpty.add(r.reviewId());   // 지워진 글 등은 이번 서버 실행 동안 다시 시도하지 않음
                    String type = e.getFailType();
                    if (type != null && (type.endsWith("403") || type.endsWith("429"))) {
                        stoppedBy = type + " — 사이트가 접근을 제한해 이번 실행을 멈췄습니다. 잠시 뒤 다시 실행하세요.";
                        break;
                    }
                    log.info("과목 언급 채우기 실패 {} ({})", r.url(), e.getMessage());
                }
            }
            int remain = remaining();
            String msg = "대상 " + rows.size() + "건 처리 · 과목 언급이 나온 후기 " + withMentions + "건 · 저장 " + saved
                    + "줄 · 아직 확인 안 한 후기 약 " + remain + "건";
            log.info("과목 언급 채우기: {}", msg);
            return new Result(msg, rows.size(), fetched, withMentions, saved, skipped, failed, stoppedBy, samples);
        } finally {
            progUrl = null;
            running.set(false);
        }
    }

    /** 남은 양·진행 상황. 실행 중이 아니어도 남은 후기 수를 알려 준다 */
    public Status status() {
        if (!mentions.tableExists()) return new Status(false, false, 0, 0, 0, 0, 0, 0, null, false, 0, null);
        return new Status(true, running.get(), progDone, progTarget, progWith, progSaved,
                remaining(), checkedEmpty.size(), progUrl, autoRunning.get(), autoRounds, autoMessage);
    }

    /**
     * 과목 언급이 아직 없는 후기. 이번 서버 실행에서 이미 확인한 후기는 뺀다.
     * [11-16] VALID 후기 먼저, 그 안에서 최신 글부터 (확인 기록은 메모리에만 있어 재시작하면 처음부터 다시 읽기 때문에,
     *         오래된 "언급 없음" 글을 다시 읽느라 새 후기에 늦게 도달하던 문제를 줄인다)
     */
    private List<Row> targets(int n) {
        List<Row> out = new ArrayList<>();
        jdbc.query("""
                SELECT r.review_id, r.source_url, r.certification_id, r.daily_minutes, r.total_hours
                FROM PASS_REVIEWS r
                WHERE (r.source_url LIKE 'https://velog.io/%' OR r.source_url LIKE '%.tistory.com/%')
                  AND NOT EXISTS (SELECT 1 FROM REVIEW_SUBJECT_MENTIONS m WHERE m.review_id = r.review_id)
                ORDER BY (r.review_status = 'VALID') DESC, r.review_id DESC
                """, rs -> {
            if (out.size() >= n) return;
            long id = rs.getLong("review_id");
            if (checkedEmpty.contains(id)) return;
            out.add(new Row(id, rs.getString("source_url"), rs.getLong("certification_id"),
                    (Integer) rs.getObject("daily_minutes", Integer.class),
                    rs.getBigDecimal("total_hours")));
        });
        return out;
    }

    private int remaining() {
        Integer total = jdbc.queryForObject("""
                SELECT COUNT(*) FROM PASS_REVIEWS r
                WHERE (r.source_url LIKE 'https://velog.io/%' OR r.source_url LIKE '%.tistory.com/%')
                  AND NOT EXISTS (SELECT 1 FROM REVIEW_SUBJECT_MENTIONS m WHERE m.review_id = r.review_id)
                """, Integer.class);
        return Math.max(0, (total == null ? 0 : total) - checkedEmpty.size());   // 확인했지만 언급이 없던 글은 뺀다
    }
}
