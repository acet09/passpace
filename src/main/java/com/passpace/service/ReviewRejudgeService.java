package com.passpace.service;

import com.passpace.client.NaverCafeClient;
import com.passpace.client.ReviewPageFetcher;
import com.passpace.constant.ExamType;
import com.passpace.crawler.AuthorHasher;
import com.passpace.crawler.NaverBlogPageParser;
import com.passpace.crawler.PostPageParser.PostPage;
import com.passpace.crawler.ReviewSite;
import com.passpace.crawler.ReviewUrlLedger;
import com.passpace.domain.ExtractedReview;
import com.passpace.dto.collect.CollectDtos.CollectJobStatus;
import com.passpace.dto.collect.CollectDtos.FetchedPage;
import com.passpace.dto.collect.CollectDtos.QualityResult;
import com.passpace.error.exception.CollectException;
import com.passpace.repository.ExamRoundRepository;
import com.passpace.repository.JdbcReviewSubjectMentionRepository;
import com.passpace.repository.PassReviewRepository;
import com.passpace.repository.PassReviewRepository.RejudgeTarget;
import com.passpace.service.ReviewQualityChecker.PageContext;
import org.jsoup.Jsoup;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/**
 * [용성·11-23] 이미 저장한 후기의 본문을 다시 읽어 같은 행을 다시 판정한다 (테이블 구조 변경 없음, 새 행 추가 없음).
 *
 *  - NAVER_BLOG : 네이버 검색 API 로 모은 블로그 후기는 제목·요약문만 있어 VALID 가 될 수 없었다.
 *                 모바일 글 주소(m.blog.naver.com)에서 본문을 읽어 추출·검사를 다시 한다.
 *                 작성일이 3년보다 오래된 글은 요청하지 않는다 (어차피 통계에서 제외).
 *  - NAVER_CAFE : 네이버 카페 요약문 후기. 가입한 카페(passpace.collect.naver.cafe-clubs)의 글만, 프로젝트 계정 로그인 쿠키로 본문을 읽는다
 *                 (NaverCafeClient). 권한 없는 글(등업 필요 등)은 건너뛰고, 연달아 계속 권한이 없으면 멈춘다 (쿠키 만료 의심)
 *  - NO_TIME    : 티스토리·velog 크롤링 후기 중 "시간 정보 없음"으로 제외된 글을 보강된 시간 규칙(11-23)으로 다시 판정한다.
 *
 * 판정 규칙은 크롤링 영역(ReviewCollectServiceImpl.analyze)과 같다: 추출 → SQLD·ADsP 필기 고정 → 공식 시험일 대조 → 품질 검사.
 * 크롤링·네이버 검색과 동시에 돌지 않는다 (CollectRunGuard 의 네이버 표시를 함께 쓴다).
 * 403·429(접근 제한)를 받으면 즉시 멈춘다. 처리한 행은 사유가 바뀌므로 다음 실행에서 다시 고르지 않는다 → 멈춘 곳부터 이어서 실행된다.
 * 끝나면 참고 학습시간을 다시 집계한다.
 */
@Service
public class ReviewRejudgeService {

    private static final Logger log = LoggerFactory.getLogger(ReviewRejudgeService.class);
    public static final String NAVER_BLOG = "NAVER_BLOG";
    public static final String NO_TIME = "NO_TIME";
    public static final String NAVER_CAFE = "NAVER_CAFE";
    /** 한 카페에서 권한 없음이 연달아 이만큼 나면 그 카페는 이번 실행에서 건너뛴다 (등업 전). 모든 카페가 막히면 멈춘다 (쿠키 만료 의심) */
    private static final int MAX_CONSECUTIVE_DENIED = 15;
    /** 네트워크 오류가 연달아 이만큼 나면 멈춘다 (PC 인터넷이 끊긴 경우) */
    private static final int MAX_CONSECUTIVE_FAIL = 20;
    /** 본문이 이보다 짧으면 읽기 실패로 보고 행을 바꾸지 않는다 */
    private static final int MIN_BODY_CHARS = 30;

    private final ReviewPageFetcher fetcher;
    private final NaverCafeClient cafeClient;
    private final ReviewExtractor extractor;
    private final ReviewQualityChecker qualityChecker;
    private final PassReviewRepository reviewRepository;
    private final ExamRoundRepository examRoundRepository;
    private final AuthorHasher authorHasher;
    private final ReviewCollectService crawlService;
    private final CollectRunGuard runGuard;
    private final StudyReferenceAggregator referenceAggregator;
    private final ReviewUrlLedger ledger;
    private final int maxChars;
    private final SubjectStudyExtractor subjectExtractor = new SubjectStudyExtractor();
    private JdbcReviewSubjectMentionRepository subjectMentions;

    private final AtomicReference<Run> current = new AtomicReference<>();

    @Autowired(required = false)
    void setSubjectMentions(JdbcReviewSubjectMentionRepository subjectMentions) {
        this.subjectMentions = subjectMentions;
    }

    public ReviewRejudgeService(ReviewPageFetcher fetcher, NaverCafeClient cafeClient, ReviewExtractor extractor, ReviewQualityChecker qualityChecker,
                                PassReviewRepository reviewRepository, ExamRoundRepository examRoundRepository,
                                AuthorHasher authorHasher, ReviewCollectService crawlService, CollectRunGuard runGuard,
                                StudyReferenceAggregator referenceAggregator, ReviewUrlLedger ledger,
                                @Value("${passpace.collect.review-max-chars}") int maxChars) {
        this.fetcher = fetcher;
        this.cafeClient = cafeClient;
        this.extractor = extractor;
        this.qualityChecker = qualityChecker;
        this.reviewRepository = reviewRepository;
        this.examRoundRepository = examRoundRepository;
        this.authorHasher = authorHasher;
        this.crawlService = crawlService;
        this.runGuard = runGuard;
        this.referenceAggregator = referenceAggregator;
        this.ledger = ledger;
        this.maxChars = maxChars;
    }

    // =====================================================================
    // 시작 · 상태 · 중단 · 대상 수
    // =====================================================================

    /** 재판정 대상 수 (네트워크 요청 없음). 시작 전에 규모를 보는 용도 */
    public Map<String, Integer> targetCounts() {
        Map<String, Integer> m = new LinkedHashMap<>();
        m.put(NAVER_BLOG, reviewRepository.listForRejudge(NAVER_BLOG, threeYearsAgo(), Integer.MAX_VALUE).size());
        m.put(NAVER_CAFE, cafeTargets(Integer.MAX_VALUE).size());
        m.put(NO_TIME, reviewRepository.listForRejudge(NO_TIME, threeYearsAgo(), Integer.MAX_VALUE).size());
        return m;
    }

    /**
     * 카페 대상: 가입한 카페(cafe-clubs) 글만, 카페를 번갈아 가며 limit 건.
     * (한 카페 글이 앞에 몰리면 시험 실행이 그 카페만 보게 되고, 등업 전 카페 때문에 다른 카페가 밀린다)
     */
    private List<RejudgeTarget> cafeTargets(int limit) {
        List<String> clubs = cafeClient.clubs();
        Map<String, java.util.ArrayDeque<RejudgeTarget>> byClub = new LinkedHashMap<>();
        for (String c : clubs) byClub.put(c, new java.util.ArrayDeque<>());
        for (RejudgeTarget t : reviewRepository.listForRejudge(NAVER_CAFE, threeYearsAgo(), Integer.MAX_VALUE)) {
            String c = clubOf(t.url());
            if (c != null && byClub.containsKey(c)) byClub.get(c).add(t);     // 합격 언급 글이 먼저인 순서 유지
        }
        List<RejudgeTarget> out = new java.util.ArrayList<>();
        int max = Math.max(1, limit);
        boolean added = true;
        while (out.size() < max && added) {
            added = false;
            for (java.util.ArrayDeque<RejudgeTarget> q : byClub.values()) {
                if (out.size() >= max) break;
                RejudgeTarget t = q.poll();
                if (t != null) {
                    out.add(t);
                    added = true;
                }
            }
        }
        return out;
    }

    /**
     * @param mode  NAVER_BLOG / NO_TIME
     * @param limit 이번 실행에서 처리할 최대 건수 (시험 실행은 20 정도)
     */
    public synchronized CollectJobStatus start(String mode, int limit) {
        Run cur = current.get();
        if (cur != null && "RUNNING".equals(cur.state)) return cur.status();
        if (!NAVER_BLOG.equals(mode) && !NAVER_CAFE.equals(mode) && !NO_TIME.equals(mode)) {
            return Run.message("IDLE", mode, "mode 는 NAVER_BLOG, NAVER_CAFE, NO_TIME 중 하나입니다.");
        }
        if (NAVER_CAFE.equals(mode) && !cafeClient.hasCookie()) {
            return Run.message("IDLE", mode, "카페 로그인 쿠키가 없습니다. application-local.yml 의 passpace.collect.naver.cafe-cookie 에"
                    + " \"NID_AUT=…; NID_SES=…\" 를 넣고 서버를 다시 켜세요.");
        }
        if ("RUNNING".equals(crawlService.jobStatus().state())) {
            return Run.message("IDLE", mode, "크롤링 영역이 실행 중이라 시작하지 않았습니다. 끝난 뒤 다시 누르세요.");
        }
        if (!runGuard.beginNaver()) {
            return Run.message("IDLE", mode, "네이버 검색 수집(또는 다른 재판정)이 실행 중이라 시작하지 않았습니다.");
        }
        List<RejudgeTarget> targets;
        try {
            targets = NAVER_CAFE.equals(mode) ? cafeTargets(limit)
                    : reviewRepository.listForRejudge(mode, threeYearsAgo(), Math.max(1, limit));
        } catch (RuntimeException e) {
            runGuard.endNaver();
            throw e;
        }
        Run run = new Run(mode, targets);
        current.set(run);
        Thread t = new Thread(() -> {
            String state = "DONE";
            try {
                state = execute(run);
            } catch (Exception e) {
                state = "STOPPED";
                run.stopReason = "예상하지 못한 오류: " + e.getMessage();
                log.warn("재판정 실행 오류", e);
            } finally {
                try {
                    if (run.updated.get() > 0) {
                        referenceAggregator.refreshAll();
                        run.notes.add("참고 학습시간 자동 집계 완료");
                    }
                } catch (Exception e) {
                    run.notes.add("참고 학습시간 자동 집계 실패: " + e.getMessage());
                }
                run.finish(state);
                runGuard.endNaver();
            }
        }, "review-rejudge-job");
        t.setDaemon(true);
        t.start();
        return run.status();
    }

    public CollectJobStatus status() {
        Run run = current.get();
        return run == null ? Run.message("IDLE", null, "이번 서버 실행 중 재판정을 한 적이 없습니다.") : run.status();
    }

    public CollectJobStatus cancel() {
        Run run = current.get();
        if (run != null && "RUNNING".equals(run.state)) run.cancelled = true;
        return status();
    }

    // =====================================================================
    // 실행
    // =====================================================================

    private String execute(Run run) {
        int consecutiveFail = 0;
        Map<String, Integer> deniedInRow = new LinkedHashMap<>();       // 카페별 연속 권한 없음
        java.util.Set<String> blockedClubs = new java.util.LinkedHashSet<>();
        for (RejudgeTarget target : run.targets) {
            if (run.cancelled) break;
            String club = NAVER_CAFE.equals(run.mode) ? clubOf(target.url()) : null;
            if (club != null && blockedClubs.contains(club)) {
                run.clubSkipped.incrementAndGet();          // 등업 전 카페 → 요청하지 않고 다음 실행으로 미룸
                run.processed.incrementAndGet();
                continue;
            }
            run.phase = run.processed.get() + 1 + "/" + run.targets.size();
            try {
                Judged j = switch (run.mode) {
                    case NAVER_BLOG -> judgeNaver(target);
                    case NAVER_CAFE -> judgeCafe(target);
                    default -> judgeCrawled(target);
                };
                consecutiveFail = 0;
                if (club != null) deniedInRow.put(club, 0);
                if (j == null) {
                    run.bodyMissing.incrementAndGet();
                    ledger.record(target.url(), siteName(run.mode, target.url()), "REJUDGE:NO_BODY");
                    continue;
                }
                reviewRepository.updateFromBody(target.reviewId(), j.postedAt(), j.review(), j.quality());
                if (subjectMentions != null && !j.subjects().isEmpty()) {
                    subjectMentions.saveForReview(target.reviewId(), target.certificationId(), j.subjects());
                }
                run.updated.incrementAndGet();
                run.byStatus.computeIfAbsent(j.quality().reviewStatus(), k -> new AtomicInteger()).incrementAndGet();
                ledger.record(target.url(), siteName(run.mode, target.url()), "REJUDGE:" + j.quality().reviewStatus());
            } catch (CollectException e) {
                if ("CAFE_DENIED".equals(e.getFailType())) {
                    // 등업이 필요하거나 삭제된 글 → 건너뜀 (행은 그대로)
                    run.denied.incrementAndGet();
                    ledger.record(target.url(), siteName(run.mode, target.url()), "REJUDGE:DENIED");
                    if (run.firstDenied == null) run.firstDenied = e.getMessage();
                    if (club != null && deniedInRow.merge(club, 1, Integer::sum) >= MAX_CONSECUTIVE_DENIED) {
                        blockedClubs.add(club);
                        run.notes.add(club + ": 연속 " + MAX_CONSECUTIVE_DENIED + "건 권한 없음 → 이번 실행에서 건너뜀 (등업 후 다시 실행)");
                        if (blockedClubs.containsAll(cafeClient.clubs())) {
                            run.stopReason = "모든 카페에서 연속 권한 없음 → 쿠키 만료·차단을 확인하세요. 예: " + e.getMessage();
                            break;
                        }
                    }
                    continue;
                }
                run.failed.incrementAndGet();
                ledger.record(target.url(), siteName(run.mode, target.url()), "REJUDGE_FAIL:" + e.getFailType());
                String type = e.getFailType();
                if ("HTTP_403".equals(type) || "HTTP_429".equals(type) || "COOLDOWN".equals(type)) {
                    run.stopReason = e.getMessage();
                    break;
                }
                if (++consecutiveFail >= MAX_CONSECUTIVE_FAIL) {
                    run.stopReason = "연속 " + MAX_CONSECUTIVE_FAIL + "건 실패 (인터넷 연결 확인): " + e.getMessage();
                    break;
                }
                log.info("재판정 건너뜀 {}: {}", target.url(), e.getMessage());
            } catch (Exception e) {
                run.failed.incrementAndGet();
                log.warn("재판정 실패 {}: {}", target.url(), e.getMessage());
            } finally {
                run.processed.incrementAndGet();
            }
        }
        run.phase = null;
        if (NAVER_CAFE.equals(run.mode)) {
            run.notes.add("카페 본문 경로: " + (cafeClient.lastRoute() == null ? "없음" : cafeClient.lastRoute()));
            if (run.firstDenied != null) run.notes.add("권한 없음 첫 사례: " + run.firstDenied);
        }
        if (run.stopReason != null) return "STOPPED";
        if (run.cancelled) return "CANCELLED";
        return "DONE";
    }

    /** 판정 결과 (본문 원문 없음) */
    record Judged(LocalDate postedAt, ExtractedReview review, QualityResult quality,
                  List<SubjectStudyExtractor.Mention> subjects) {
    }

    /** 네이버 블로그: 모바일 주소에서 본문을 읽는다. 본문 영역을 못 찾으면 null (행을 바꾸지 않음) */
    Judged judgeNaver(RejudgeTarget t) {
        String mobile = NaverBlogPageParser.mobileUrl(t.url());
        if (mobile == null) return null;
        String html = fetcher.fetchListing(mobile);
        PostPage page = NaverBlogPageParser.parse(Jsoup.parse(html, mobile), LocalDate.now(), maxChars);
        if (page.text().length() < MIN_BODY_CHARS) return null;
        LocalDate postedAt = t.postedAt() != null ? t.postedAt() : page.postedAt();
        return judge(t, page.title(), page.text(), postedAt, page.noReprint());
    }

    /** 네이버 카페: 로그인 쿠키로 글 API 의 본문을 읽는다. 권한이 없으면 CollectException("CAFE_DENIED") */
    Judged judgeCafe(RejudgeTarget t) {
        NaverCafeClient.CafeArticle a = cafeClient.fetch(t.url());
        String text = a.text().length() > maxChars ? a.text().substring(0, maxChars) : a.text();
        if (text.length() < MIN_BODY_CHARS) return null;
        LocalDate postedAt = a.postedAt() != null ? a.postedAt() : t.postedAt();
        return judge(t, a.title(), text, postedAt, NaverBlogPageParser.noReprint(a.text()));
    }

    /** 티스토리·velog: 크롤링 영역과 같은 방식으로 글을 읽는다 */
    Judged judgeCrawled(RejudgeTarget t) {
        Optional<ReviewSite> site = ReviewSite.of(t.url());
        if (site.isEmpty()) return null;
        FetchedPage page = fetcher.fetchPost(t.url(), site.get(), authorHasher);
        if (page.text() == null || page.text().length() < MIN_BODY_CHARS) return null;
        LocalDate postedAt = page.postedAt() != null ? page.postedAt() : t.postedAt();
        return judge(t, page.title(), page.text(), postedAt, page.noReprint());
    }

    /** 크롤링 영역(ReviewCollectServiceImpl.analyze)과 같은 판정. 자격증은 저장된 행의 값을 그대로 쓴다 */
    Judged judge(RejudgeTarget t, String title, String text, LocalDate postedAt, boolean noReprint) {
        text = CertificateDetector.textFor(t.certCode(), title, text);   // [11-26] 수집과 같은 구간 판정
        ExtractedReview review = extractor.extract(title, text);
        if (CertificateDetector.writtenOnly(t.certCode()) && review.examType() != ExamType.WRITTEN) {
            review = RuleBasedReviewExtractor.withExamType(review, ExamType.WRITTEN);
        }
        LocalDate officialDate = null;
        if (review.examYear() != null && review.roundNo() != null && review.examType() != null) {
            officialDate = examRoundRepository
                    .find(t.certificationId(), review.examYear(), review.roundNo(), review.examType().name())
                    .map(ExamRoundRepository.StoredRound::examStart).orElse(null);
        }
        QualityResult quality = qualityChecker.check(review, text,
                new PageContext(postedAt, LocalDate.now(), noReprint, officialDate));
        if (noReprint) {
            review = new ExtractedReview(null, null, null, null, null, null, null, null, null, null, false, null);
        }
        List<SubjectStudyExtractor.Mention> subjects = noReprint ? List.of()
                : subjectExtractor.extract((title == null ? "" : title) + "\n" + text, review.dailyMinutes(), review.totalHours());
        return new Judged(postedAt, review, quality, subjects);
    }

    private static String siteName(String mode, String url) {
        if (NAVER_BLOG.equals(mode)) return "NAVER_BLOG";
        if (NAVER_CAFE.equals(mode)) return "NAVER_CAFE";
        return ReviewSite.of(url).map(Enum::name).orElse("OTHER");
    }

    private static String clubOf(String url) {
        String[] p = NaverCafeClient.parseUrl(url);
        return p == null ? null : p[0];
    }

    private static LocalDate threeYearsAgo() {
        return LocalDate.now().minusYears(ReviewQualityChecker.MAX_AGE_YEARS);
    }

    // =====================================================================
    // 실행 1회 상태
    // =====================================================================

    private static final class Run {
        final String mode;
        final List<RejudgeTarget> targets;
        final Instant startedAt = Instant.now();
        final AtomicInteger processed = new AtomicInteger(), updated = new AtomicInteger(),
                bodyMissing = new AtomicInteger(), failed = new AtomicInteger(), denied = new AtomicInteger(),
                clubSkipped = new AtomicInteger();
        volatile String firstDenied;
        final Map<String, AtomicInteger> byStatus = new ConcurrentHashMap<>();
        final List<String> notes = new CopyOnWriteArrayList<>();
        volatile String state = "RUNNING";
        volatile String phase;
        volatile boolean cancelled;
        volatile String stopReason;
        volatile Instant finishedAt;

        Run(String mode, List<RejudgeTarget> targets) {
            this.mode = mode;
            this.targets = targets;
        }

        void finish(String s) {
            finishedAt = Instant.now();
            state = s;
        }

        CollectJobStatus status() {
            Map<String, String> m = new LinkedHashMap<>();
            for (String s : List.of("VALID", "PENDING", "EXCLUDED")) {
                m.put(s, String.valueOf(byStatus.getOrDefault(s, new AtomicInteger()).get()));
            }
            m.put("본문 없음", String.valueOf(bodyMissing.get()));
            if (NAVER_CAFE.equals(mode)) {
                m.put("권한 없음", String.valueOf(denied.get()));
                m.put("등업 전 카페라 미룸", String.valueOf(clubSkipped.get()));
            }
            Instant end = finishedAt == null ? Instant.now() : finishedAt;
            StringBuilder msg = new StringBuilder();
            if (stopReason != null) msg.append("중단: ").append(stopReason).append(" ");
            if (cancelled) msg.append("관리자가 중단했습니다. ");
            if (!notes.isEmpty()) msg.append("| ").append(String.join(" / ", notes));
            return new CollectJobStatus(state, mode, targets.size(), targets.size(), processed.get(), updated.get(),
                    byStatus.getOrDefault("VALID", new AtomicInteger()).get(), bodyMissing.get(), failed.get(), 0, m,
                    startedAt.toString(), Duration.between(startedAt, end).toSeconds(), msg.toString().strip(),
                    "REJUDGE", failed.get(), finishedAt == null ? phase : null);
        }

        static CollectJobStatus message(String state, String mode, String message) {
            return new CollectJobStatus(state, mode, 0, 0, 0, 0, 0, 0, 0, 0, Map.of(), null, 0, message, "REJUDGE", 0, null);
        }
    }
}
