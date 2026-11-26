package com.passpace.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.passpace.client.NaverCafeClient;
import com.passpace.client.NaverSearchClient;
import com.passpace.client.ReviewPageFetcher;
import com.passpace.constant.ExamType;
import com.passpace.crawler.NaverBlogPageParser;
import com.passpace.crawler.PostPageParser.PostPage;
import com.passpace.domain.ExtractedReview;
import com.passpace.dto.collect.CollectDtos.QualityResult;
import com.passpace.error.exception.CollectException;
import com.passpace.service.ReviewQualityChecker.PageContext;
import org.jsoup.Jsoup;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/**
 * [용성·11-24] 새 자격증 후보의 데이터 확보 가능성 시험 실행 (probe).
 *
 * 자격증을 DB 에 등록하기 전에 "기존 4종처럼 바로 추가 가능한지"를 데이터 양으로 판정한다.
 *  1단계 검색: 자격증마다 검색어 3개 × (blog, cafearticle) × 정렬(sim, date) → total 기록, 고유 URL 모으기, 판별·제외 키워드로 거르기
 *  2단계 본문 표본: 블로그 최대 sample 건(최근 3년 글 먼저, 섞기), 카페는 쿠키가 있을 때만 최대 cafeSample 건.
 *                  기존 4종과 같은 추출기·품질 검사기로 판정. 글 1건당 판정 시간 제한 10초
 *  3단계 계산: 예상 합격 후기 = 고유 URL 수 × 표본의 "VALID 이면서 합격" 비율 (95% 신뢰구간 함께)
 *
 * DB 에 아무것도 쓰지 않는다: 리포지토리·JdbcTemplate 을 주입받지 않는다. 결과는 메모리와 collect-data/probe/ 리포트 파일에만 둔다.
 * 네이버 수집·재판정과 동시에 돌지 않는다 (CollectRunGuard 의 네이버 표시를 함께 쓴다).
 * 403·429(접근 제한)를 받으면 즉시 멈춘다.
 */
@Service
public class CandidateProbeService {

    private static final Logger log = LoggerFactory.getLogger(CandidateProbeService.class);

    /** 후보 자격증: 판별 키워드(하나라도 있어야 함), 제외 키워드(제목에 있으면 다른 자격증 글로 보고 뺌), 필기만 있는 시험 여부 */
    public record Candidate(String name, List<String> include, List<String> exclude, boolean writtenOnly) {
    }

    public static final Map<String, Candidate> CANDIDATES = new LinkedHashMap<>();

    static {
        add(new Candidate("산업안전기사", List.of("산업안전기사", "산안기"), List.of("산업안전산업기사", "건설안전기사"), false));
        add(new Candidate("전산회계 1급", List.of("전산회계 1급", "전산회계1급", "전회1"), List.of("전산회계 2급", "전산회계2급", "전산세무"), true));
        add(new Candidate("빅데이터분석기사", List.of("빅데이터분석기사", "빅데이터 분석기사", "빅분기"), List.of("ADsP", "ADP"), false));
        add(new Candidate("전기기사", List.of("전기기사"), List.of("전기산업기사", "전기기능사", "전기공사기사"), false));
        add(new Candidate("직업상담사 2급", List.of("직업상담사 2급", "직업상담사2급"), List.of("직업상담사 1급", "직업상담사1급"), false));
        add(new Candidate("사회조사분석사 2급", List.of("사회조사분석사 2급", "사회조사분석사2급", "사조사 2급", "사조사2급"),
                List.of("사회조사분석사 1급", "사회조사분석사1급"), false));
        // [11-25] IT 후보 추가
        add(new Candidate("정보보안기사", List.of("정보보안기사", "정보보안 기사"), List.of("정보보안산업기사"), false));
        add(new Candidate("리눅스마스터 2급", List.of("리눅스마스터 2급", "리눅스마스터2급", "리눅스 마스터 2급"),
                List.of("리눅스마스터 1급", "리눅스마스터1급"), false));
        add(new Candidate("네트워크관리사 2급", List.of("네트워크관리사 2급", "네트워크관리사2급", "네관사 2급"),
                List.of("네트워크관리사 1급", "네트워크관리사1급"), false));
        // [11-26] 추가 후보: 컴활 2급, 전산회계 2급, 정보처리산업기사
        add(new Candidate("컴활 2급", List.of("컴활 2급", "컴활2급", "컴퓨터활용능력 2급", "컴퓨터활용능력2급"),
                List.of("컴활 1급", "컴활1급", "컴퓨터활용능력 1급", "컴퓨터활용능력1급"), false));
        add(new Candidate("전산회계 2급", List.of("전산회계 2급", "전산회계2급", "전회2"),
                List.of("전산회계 1급", "전산회계1급", "전산세무"), true));
        add(new Candidate("정보처리산업기사", List.of("정보처리산업기사", "정보처리 산업기사", "정처산기"),
                List.of("정보처리기능사"), false));
    }

    private static void add(Candidate c) {
        CANDIDATES.put(c.name(), c);
    }

    /** [11-24] 서버 실행 옵션용 영문 코드 (PowerShell 에서 한글·띄어쓰기가 깨지지 않게) */
    public static final Map<String, String> CODES = Map.ofEntries(
            Map.entry("SAFETY", "산업안전기사"),
            Map.entry("ACCOUNTING", "전산회계 1급"),
            Map.entry("BIGDATA", "빅데이터분석기사"),
            Map.entry("ELECTRIC", "전기기사"),
            Map.entry("COUNSELOR", "직업상담사 2급"),
            Map.entry("SURVEY", "사회조사분석사 2급"),
            Map.entry("SECURITY", "정보보안기사"),
            Map.entry("LINUX", "리눅스마스터 2급"),
            Map.entry("NETWORK", "네트워크관리사 2급"),
            Map.entry("COMPUTER2", "컴활 2급"),
            Map.entry("ACCOUNTING2", "전산회계 2급"),
            Map.entry("INFOIND", "정보처리산업기사"));

    /** 영문 코드면 자격증 이름으로 바꾸고, 이름이면 그대로 */
    static String resolve(String nameOrCode) {
        String t = nameOrCode == null ? "" : nameOrCode.strip();
        return CODES.getOrDefault(t.toUpperCase(Locale.ROOT), t);
    }

    /** 기존 4종: 한 글에 함께 나오면 "여러 자격증"으로 따로 센다 */
    static final List<String> EXISTING = List.of("정보처리기사", "정처기", "SQLD", "컴활", "컴퓨터활용능력", "ADsP");

    static final List<String> QUERY_SUFFIX = List.of(" 합격 후기", " 공부시간", " 비전공 합격");
    /** [11-24] 검색 상한(검색어당 약 1,100건) 때문에 고유 URL 이 적게 잡히는 자격증용 추가 검색어 (more=true 일 때) */
    static final List<String> EXTRA_SUFFIX = List.of(" 필기 합격 후기", " 실기 합격 후기", " 필기 후기", " 실기 후기", " 독학 합격", " 합격 수기");
    private static final List<String> TYPES = List.of("blog", "cafearticle");
    private static final List<String> SORTS = List.of("sim", "date");
    private static final int DISPLAY = 100;
    private static final int MAX_START = 1000;
    /** 글 1건 판정 시간 제한 (정규식이 끝나지 않는 글을 건너뛴다) */
    static final long JUDGE_TIMEOUT_MS = 10_000;
    private static final int MIN_BODY_CHARS = 30;
    /** 판정 기준 (예상 합격 후기) */
    static final int POSSIBLE = 500;
    static final int HOLD = 300;
    static final int EXAM_TYPE_WARN = 100;

    private final NaverSearchClient searchClient;
    private final ReviewPageFetcher fetcher;
    private final NaverCafeClient cafeClient;
    private final ReviewExtractor extractor;
    private final ReviewQualityChecker qualityChecker;
    private final CollectRunGuard runGuard;
    private final ReviewCollectService crawlService;
    private final ObjectMapper objectMapper;
    private final int maxChars;
    private final Path reportDir;

    private final AtomicReference<Run> current = new AtomicReference<>();

    /** [11-24] 실행 신호 파일 확인 주기 (초) */
    private static final int TRIGGER_POLL_SECONDS = 10;
    private volatile Map<String, Object> lastReport;

    public CandidateProbeService(NaverSearchClient searchClient, ReviewPageFetcher fetcher, NaverCafeClient cafeClient,
                                 ReviewExtractor extractor, ReviewQualityChecker qualityChecker, CollectRunGuard runGuard,
                                 ReviewCollectService crawlService, ObjectMapper objectMapper,
                                 @Value("${passpace.collect.review-max-chars}") int maxChars,
                                 @Value("${passpace.collect.data-dir:collect-data}") String dataDir) {
        this.searchClient = searchClient;
        this.fetcher = fetcher;
        this.cafeClient = cafeClient;
        this.extractor = extractor;
        this.qualityChecker = qualityChecker;
        this.runGuard = runGuard;
        this.crawlService = crawlService;
        this.objectMapper = objectMapper.copy().enable(SerializationFeature.INDENT_OUTPUT);
        this.maxChars = maxChars;
        this.reportDir = Paths.get(dataDir).toAbsolutePath().normalize().resolve("probe");
    }

    // =====================================================================
    // 시작 · 상태 · 중단 · 리포트
    // =====================================================================

    public Map<String, Object> start(List<String> certNames, int sample, int cafeSample) {
        return start(certNames, sample, cafeSample, false);
    }

    /** @param more true 이면 추가 검색어(EXTRA_SUFFIX)까지 써서 고유 URL 을 넓힌다 */
    public synchronized Map<String, Object> start(List<String> certNames, int sample, int cafeSample, boolean more) {
        certNames = certNames.stream().map(CandidateProbeService::resolve).toList();
        Run cur = current.get();
        if (cur != null && "RUNNING".equals(cur.state)) return cur.status();
        List<Candidate> certs = new ArrayList<>();
        List<String> unknown = new ArrayList<>();
        for (String n : certNames) {
            Candidate c = CANDIDATES.get(n == null ? "" : n.strip());
            if (c == null) unknown.add(n);
            else if (!certs.contains(c)) certs.add(c);
        }
        if (!unknown.isEmpty() || certs.isEmpty()) {
            return message("IDLE", "알 수 없는 자격증: " + unknown + ". 가능한 값: " + CANDIDATES.keySet());
        }
        if (!searchClient.hasKey()) return message("IDLE", "네이버 검색 API 키가 없습니다.");
        if ("RUNNING".equals(crawlService.jobStatus().state())) {
            return message("IDLE", "크롤링 영역이 실행 중이라 시작하지 않았습니다.");
        }
        if (!runGuard.beginNaver()) {
            return message("IDLE", "네이버 검색 수집 또는 재판정이 실행 중이라 시작하지 않았습니다.");
        }
        Run run = new Run(certs, Math.max(10, Math.min(500, sample)), Math.max(0, Math.min(200, cafeSample)));
        if (more) run.suffixes.addAll(EXTRA_SUFFIX);
        current.set(run);
        Thread t = new Thread(() -> {
            String state = "DONE";
            try {
                state = execute(run);
            } catch (Exception e) {
                state = "STOPPED";
                run.stopReason = "예상하지 못한 오류: " + e.getMessage();
                log.warn("후보 자격증 시험 실행 오류", e);
            } finally {
                run.finish(state);
                try {
                    writeReport(run);
                } catch (Exception e) {
                    run.notes.add("리포트 저장 실패: " + e.getMessage());
                } finally {
                    run.reported = true;
                }
                runGuard.endNaver();
                run.shutdownJudge();
            }
        }, "candidate-probe-job");
        t.setDaemon(true);
        t.start();
        startStatusWriter(run);
        return run.status();
    }

    /**
     * [11-24] 실행 신호 파일 방식 (관리자 토큰·실행 옵션 없이 실행하기 위함).
     * 서버가 켜져 있는 동안 10초마다 collect-data/probe/run.txt 가 있는지 확인한다.
     * 내용 예: "SAFETY,BIGDATA,ACCOUNTING more"  (선택: sample=150 cafe=50)
     *         "cancel" 이면 실행 중인 시험 실행을 중단한다.
     * 읽은 파일은 run.done 으로 이름을 바꿔 한 번만 실행되게 한다. 파일이 없으면 아무 일도 하지 않는다.
     */
    @EventListener(ApplicationReadyEvent.class)
    public void startTriggerWatcher() {
        Thread w = new Thread(() -> {
            Path trigger = reportDir.resolve("run.txt");
            while (true) {
                try {
                    Thread.sleep(TRIGGER_POLL_SECONDS * 1_000L);
                    if (Files.exists(trigger)) handleTrigger(trigger);
                } catch (InterruptedException e) {
                    return;
                } catch (Exception e) {
                    log.warn("실행 신호 파일 처리 실패: {}", e.getMessage());
                }
            }
        }, "candidate-probe-trigger");
        w.setDaemon(true);
        w.start();
        log.info("후보 자격증 시험 실행: 실행 신호 파일 대기 중 ({})", reportDir.resolve("run.txt"));
    }

    void handleTrigger(Path trigger) throws IOException {
        String text = Files.readString(trigger, StandardCharsets.UTF_8).trim();
        Files.move(trigger, trigger.resolveSibling("run.done"), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        if (text.equalsIgnoreCase("cancel")) {
            writeStatusFile(cancel());
            return;
        }
        List<String> certs = new ArrayList<>();
        boolean more = false;
        int sample = 150;
        int cafeSample = 50;
        for (String token : text.split("\\s+")) {
            String t = token.trim();
            if (t.isEmpty()) continue;
            String lower = t.toLowerCase(Locale.ROOT);
            if (lower.equals("more")) more = true;
            else if (lower.startsWith("sample=")) sample = Integer.parseInt(t.substring(7));
            else if (lower.startsWith("cafe=")) cafeSample = Integer.parseInt(t.substring(5));
            else for (String c : t.split(",")) if (!c.isBlank()) certs.add(c.trim());
        }
        Map<String, Object> r = start(certs, sample, cafeSample, more);
        log.info("후보 자격증 시험 실행 신호 파일로 시작 ({}): {}", text, r.get("state"));
        if (!"RUNNING".equals(r.get("state"))) writeStatusFile(r);
    }

    /** [11-24] 실행 중 10초마다 collect-data/probe/status.json 에 상태를 쓴다 (토큰 없이 진행 확인용). 끝나면 마지막 상태 + 판정 요약 */
    private void startStatusWriter(Run run) {
        Thread w = new Thread(() -> {
            int waitReport = 0;
            while (true) {
                Map<String, Object> st = run.status();
                boolean running = "RUNNING".equals(st.get("state"));
                if (!running && !run.reported && waitReport++ < 60) {
                    try {
                        Thread.sleep(1_000);    // 리포트 파일이 저장될 때까지 잠깐 기다린다
                    } catch (InterruptedException e) {
                        return;
                    }
                    continue;
                }
                if (!running) {
                    st = new LinkedHashMap<>(st);
                    Map<String, Object> rep = lastReport;
                    if (rep != null) {
                        st.put("report", rep);
                    }
                }
                writeStatusFile(st);
                if (!running) return;
                try {
                    Thread.sleep(10_000);
                } catch (InterruptedException e) {
                    return;
                }
            }
        }, "candidate-probe-status");
        w.setDaemon(true);
        w.start();
    }

    private void writeStatusFile(Map<String, Object> st) {
        try {
            Files.createDirectories(reportDir);
            Map<String, Object> out = new LinkedHashMap<>(st);
            out.put("writtenAt", LocalDateTime.now().toString());
            Path tmp = reportDir.resolve("status.json.tmp");
            Files.writeString(tmp, objectMapper.writeValueAsString(out), StandardCharsets.UTF_8);
            Files.move(tmp, reportDir.resolve("status.json"), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        } catch (Exception e) {
            log.debug("status.json 쓰기 실패: {}", e.getMessage());
        }
    }

    public Map<String, Object> status() {
        Run run = current.get();
        return run == null ? message("IDLE", "이번 서버 실행 중 시험 실행을 한 적이 없습니다.") : run.status();
    }

    public Map<String, Object> cancel() {
        Run run = current.get();
        if (run != null && "RUNNING".equals(run.state)) run.cancelled = true;
        return status();
    }

    /** 마지막 결과. 실행 중이면 지금까지의 중간 결과 */
    public Map<String, Object> report() {
        Run run = current.get();
        if (run != null && "RUNNING".equals(run.state)) return buildReport(run);
        return lastReport != null ? lastReport : message("IDLE", "아직 결과가 없습니다.");
    }

    // =====================================================================
    // 실행
    // =====================================================================

    private String execute(Run run) {
        // 1단계: 검색
        for (Candidate c : run.certs) {
            if (run.cancelled) return "CANCELLED";
            CertStat s = run.stats.get(c.name());
            run.phase = "1단계 검색: " + c.name();
            try {
                search(run, c, s);
            } catch (CollectException e) {
                run.stopReason = c.name() + " 검색 중단: " + e.getMessage();
                return "STOPPED";
            }
        }
        // 2단계: 본문 표본
        for (Candidate c : run.certs) {
            if (run.cancelled) return "CANCELLED";
            CertStat s = run.stats.get(c.name());
            List<Hit> targets = pickSample(s, run.sample, run.cafeSample, cafeClient.hasCookie());
            s.sampleTarget = targets.size();
            int i = 0;
            int deniedInRow = 0;
            boolean cafeBlocked = false;
            for (Hit h : targets) {
                if (run.cancelled) return "CANCELLED";
                i++;
                run.phase = "2단계 본문: " + c.name() + " " + i + "/" + targets.size();
                if (h.cafe && cafeBlocked) {
                    s.cafeSkipped.incrementAndGet();
                    continue;
                }
                long t0 = System.currentTimeMillis();
                try {
                    Body b = h.cafe ? readCafe(h) : readBlog(h);
                    if (b == null || b.text.length() < MIN_BODY_CHARS) {
                        s.bodyMissing.incrementAndGet();
                        continue;
                    }
                    if (h.cafe) deniedInRow = 0;
                    judgeAndCount(run, c, s, h, b);
                } catch (CollectException e) {
                    if ("CAFE_DENIED".equals(e.getFailType())) {
                        s.denied.incrementAndGet();
                        if (++deniedInRow >= 10) {
                            cafeBlocked = true;
                            run.notes.add(c.name() + ": 카페 권한 없음 10건 연속 → 남은 카페 표본 건너뜀");
                        }
                        continue;
                    }
                    s.failed.incrementAndGet();
                    String type = e.getFailType();
                    if ("HTTP_403".equals(type) || "HTTP_429".equals(type) || "COOLDOWN".equals(type)) {
                        run.stopReason = "접근 제한(" + type + "): " + e.getMessage();
                        return "STOPPED";
                    }
                } catch (Exception e) {
                    s.failed.incrementAndGet();
                    log.info("후보 시험 본문 실패 {}: {}", h.url, e.getMessage());
                } finally {
                    run.done.incrementAndGet();
                    run.elapsedPerItemMs.add(System.currentTimeMillis() - t0);
                }
            }
        }
        run.phase = null;
        if (run.cancelled) return "CANCELLED";
        return "DONE";
    }

    /** 1단계: 검색어 × 종류 × 정렬로 결과를 받아 고유 URL 로 모은다 */
    private void search(Run run, Candidate c, CertStat s) {
        for (String suffix : run.suffixes) {
            String query = c.name() + suffix;
            for (String type : TYPES) {
                int total = 0;
                int fetched = 0;
                for (String sort : SORTS) {
                    for (int start = 1; start <= MAX_START; start += DISPLAY) {
                        if (run.cancelled) return;
                        NaverSearchClient.Page page = searchClient.search(type, query, sort, start, DISPLAY);
                        run.apiCalls.incrementAndGet();
                        total = Math.max(total, page.total());
                        if (page.items().isEmpty()) break;
                        for (NaverSearchClient.Item it : page.items()) {
                            fetched++;
                            addHit(s, type, it);
                        }
                        if (start + DISPLAY > page.total()) break;
                    }
                }
                s.totals.put(type + " | " + query, total);
                if (total > fetched) s.capped = true;
            }
        }
    }

    private void addHit(CertStat s, String type, NaverSearchClient.Item it) {
        boolean cafe = "cafearticle".equals(type);
        String url = cafe ? NaverSearchReviewCollectService.cafeUrl(it.link()) : NaverSearchReviewCollectService.blogUrl(it.link());
        if (url == null) return;
        if (s.seen.contains(url)) return;
        s.seen.add(url);
        String title = NaverSearchReviewCollectService.clean(it.title());
        String desc = NaverSearchReviewCollectService.clean(it.description());
        Candidate c = s.cert;
        switch (classify(c, title, desc)) {
            case NO_KEYWORD -> s.noKeyword.incrementAndGet();
            case EXCLUDED -> {
                s.excludedTitle.incrementAndGet();
                if (s.excludedExamples.size() < 3) s.excludedExamples.add(title + " | " + url);
            }
            case OK -> {
                Hit h = new Hit(url, cafe, title, desc, cafe ? null : NaverSearchReviewCollectService.postdate(it.postdate()));
                h.mixed = mentionsOther(c, title + " " + desc);
                if (cafe) s.cafeHits.add(h);
                else s.blogHits.add(h);
            }
        }
    }

    enum Match { OK, NO_KEYWORD, EXCLUDED }

    /** 판별 키워드가 제목·요약 어디에도 없으면 NO_KEYWORD, 제외 키워드가 제목에 있으면 EXCLUDED (다른 자격증 글) */
    static Match classify(Candidate c, String title, String desc) {
        String t = norm(title);
        String all = t + " " + norm(desc);
        boolean has = c.include().stream().anyMatch(k -> all.contains(norm(k)));
        if (!has) return Match.NO_KEYWORD;
        if (c.exclude().stream().anyMatch(k -> containsWord(t, norm(k)))) return Match.EXCLUDED;
        return Match.OK;
    }

    /** 요약·본문에 제외 키워드나 기존 4종이 함께 나오면 "섞임"으로 표시 (판정은 그대로 한다) */
    static boolean mentionsOther(Candidate c, String text) {
        String n = norm(text);
        for (String k : c.exclude()) if (containsWord(n, norm(k))) return true;
        for (String k : EXISTING) {
            if (c.exclude().contains(k)) continue;
            // [11-26] 후보 이름 안에 기존 자격증 이름이 들어 있으면(컴활 2급 안의 "컴활") 섞임으로 보지 않는다
            if (c.include().stream().anyMatch(i -> norm(i).contains(norm(k)))) continue;
            if (containsWord(n, norm(k))) return true;
        }
        return false;
    }

    /** [11-26] 제목에 이 자격증만 있고 다른 자격증(제외 키워드·기존 4종)은 없음 (실제 수집기 CertificateDetector 의 "제목 우선" 규칙과 같은 방향) */
    static boolean titleOnlyTarget(Candidate c, String title) {
        String t = norm(title);
        return c.include().stream().anyMatch(k -> t.contains(norm(k))) && !mentionsOther(c, title);
    }

    /**
     * [11-26] 섞인 글 분리 규칙: 본문을 줄·문장 단위로 나눠, 가장 최근에 언급된 자격증이 이 자격증인 구간만 모은다.
     * 제목에 이 자격증만 있으면 첫 언급 전 내용도 이 자격증 것으로 본다. 다른 자격증 구간(공부시간 등)은 빠진다.
     */
    static String targetSegment(Candidate c, String title, String text) {
        if (text == null) return "";
        boolean own = titleOnlyTarget(c, title);
        StringBuilder sb = new StringBuilder();
        for (String piece : text.split("\\n+|(?<=[.!?。])\\s+")) {
            String n = norm(piece);
            boolean hasTarget = c.include().stream().anyMatch(k -> n.contains(norm(k)));
            if (hasTarget) own = true;
            else if (mentionsOther(c, piece)) own = false;
            if (own) sb.append(piece).append('\n');
        }
        return sb.toString().strip();
    }

    /** 공백 제거 + 소문자 */
    static String norm(String s) {
        return s == null ? "" : s.replaceAll("\\s+", "").toLowerCase(Locale.ROOT);
    }

    /** 영문 약어(adp 등)는 앞뒤가 영문이 아닐 때만 맞은 것으로 본다 (adsp 안의 "adp" 오탐 방지 등) */
    static boolean containsWord(String haystack, String needle) {
        if (needle.isEmpty()) return false;
        boolean ascii = needle.chars().allMatch(ch -> ch < 128);
        int from = 0;
        while (true) {
            int i = haystack.indexOf(needle, from);
            if (i < 0) return false;
            if (!ascii) return true;
            boolean leftOk = i == 0 || !Character.isLetter(haystack.charAt(i - 1)) || haystack.charAt(i - 1) >= 128;
            int end = i + needle.length();
            boolean rightOk = end >= haystack.length() || !Character.isLetter(haystack.charAt(end)) || haystack.charAt(end) >= 128;
            if (leftOk && rightOk) return true;
            from = i + 1;
        }
    }

    /** 블로그: 최근 3년 글 먼저, 같은 묶음 안에서는 섞어서 sample 건. 카페: 쿠키가 있을 때만 섞어서 cafeSample 건 */
    static List<Hit> pickSample(CertStat s, int sample, int cafeSample, boolean cafeCookie) {
        LocalDate cut = LocalDate.now().minusYears(ReviewQualityChecker.MAX_AGE_YEARS);
        List<Hit> recent = new ArrayList<>();
        List<Hit> rest = new ArrayList<>();
        for (Hit h : s.blogHits) {
            if (h.postedAt != null && !h.postedAt.isBefore(cut)) recent.add(h);
            else rest.add(h);
        }
        Random rnd = new Random(20261124L);
        Collections.shuffle(recent, rnd);
        Collections.shuffle(rest, rnd);
        List<Hit> out = new ArrayList<>();
        for (Hit h : recent) if (out.size() < sample) out.add(h);
        for (Hit h : rest) if (out.size() < sample) out.add(h);
        if (cafeCookie && cafeSample > 0) {
            List<Hit> cafes = new ArrayList<>(s.cafeHits);
            Collections.shuffle(cafes, rnd);
            for (int i = 0; i < Math.min(cafeSample, cafes.size()); i++) out.add(cafes.get(i));
        }
        return out;
    }

    private record Body(String title, String text, LocalDate postedAt, boolean noReprint) {
    }

    private Body readBlog(Hit h) {
        String mobile = NaverBlogPageParser.mobileUrl(h.url);
        if (mobile == null) return null;
        String html = fetcher.fetchListing(mobile);
        PostPage page = NaverBlogPageParser.parse(Jsoup.parse(html, mobile), LocalDate.now(), maxChars);
        if (page == null || page.text() == null) return null;
        LocalDate posted = page.postedAt() != null ? page.postedAt() : h.postedAt;
        return new Body(page.title() == null ? h.title : page.title(), page.text(), posted, page.noReprint());
    }

    private Body readCafe(Hit h) {
        NaverCafeClient.CafeArticle a = cafeClient.fetch(h.url);
        String text = a.text().length() > maxChars ? a.text().substring(0, maxChars) : a.text();
        return new Body(a.title() == null ? h.title : a.title(), text, a.postedAt(), NaverBlogPageParser.noReprint(a.text()));
    }

    /** 기존 4종과 같은 판정 (자격증 행이 없으므로 공식 시험일 대조는 하지 않는다). 10초가 넘으면 시간 초과로 건너뛴다 */
    private void judgeAndCount(Run run, Candidate c, CertStat s, Hit h, Body b) {
        final boolean mixedPost = h.mixed || mentionsOther(c, b.text);
        Future<Object[]> f = run.judgeExecutor().submit(() -> {
            ExtractedReview r = extractor.extract(b.title, b.text);
            if (c.writtenOnly() && r.examType() != ExamType.WRITTEN) {
                r = RuleBasedReviewExtractor.withExamType(r, ExamType.WRITTEN);
            }
            QualityResult q = qualityChecker.check(r, b.text, new PageContext(b.postedAt, LocalDate.now(), b.noReprint, null));
            // [11-26] 섞인 글 분리 조건: 해당 자격증 구간만 잘라 다시 판정한다
            ExtractedReview rs = null;
            QualityResult qs = null;
            if (mixedPost) {
                String seg = targetSegment(c, b.title, b.text);
                if (seg.length() >= MIN_BODY_CHARS) {
                    rs = extractor.extract(b.title, seg);
                    if (c.writtenOnly() && rs.examType() != ExamType.WRITTEN) {
                        rs = RuleBasedReviewExtractor.withExamType(rs, ExamType.WRITTEN);
                    }
                    qs = qualityChecker.check(rs, seg, new PageContext(b.postedAt, LocalDate.now(), b.noReprint, null));
                }
            }
            return new Object[]{r, q, rs, qs};
        });
        Object[] res;
        try {
            res = await(f, JUDGE_TIMEOUT_MS);
        } catch (TimeoutException e) {
            run.replaceJudgeExecutor();     // 끝나지 않는 정규식 스레드는 버리고 새 스레드로 계속한다
            s.timedOut.incrementAndGet();
            if (s.timeoutExamples.size() < 3) s.timeoutExamples.add(h.url);
            return;
        } catch (Exception e) {
            s.failed.incrementAndGet();
            return;
        }
        ExtractedReview r = (ExtractedReview) res[0];
        QualityResult q = (QualityResult) res[1];
        s.count(h.cafe, r, q, mixedPost, h.url);
        if (mixedPost) s.countSplit(h.cafe, titleOnlyTarget(c, b.title), (ExtractedReview) res[2], (QualityResult) res[3]);
    }

    /** 제한 시간 안에 끝나면 결과, 아니면 작업을 취소하고 TimeoutException */
    static <T> T await(Future<T> f, long timeoutMs) throws Exception {
        try {
            return f.get(timeoutMs, TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            f.cancel(true);
            throw e;
        }
    }

    // =====================================================================
    // 3단계: 계산 · 리포트
    // =====================================================================

    /** 예상치: 모집단 n × 비율 p, 95% 신뢰구간(정규 근사) */
    static long[] estimate(int population, int hits, int sampled) {
        if (sampled <= 0) return new long[]{0, 0, 0};
        double p = (double) hits / sampled;
        double half = 1.96 * Math.sqrt(p * (1 - p) / sampled);
        double lo = Math.max(0, p - half);
        double hi = Math.min(1, p + half);
        return new long[]{Math.round(population * p), Math.round(population * lo), Math.round(population * hi)};
    }

    static String verdict(long expected) {
        if (expected >= POSSIBLE) return "가능";
        if (expected >= HOLD) return "보류";
        return "불가";
    }

    Map<String, Object> buildReport(Run run) {
        Map<String, Object> rep = new LinkedHashMap<>();
        rep.put("startedAt", run.startedAt.toString());
        rep.put("state", run.state);
        rep.put("apiCalls", run.apiCalls.get());
        rep.put("queries", List.copyOf(run.suffixes));
        rep.put("criteria", "가능 ≥" + POSSIBLE + " / 보류 " + HOLD + "~" + (POSSIBLE - 1) + " / 불가 <" + HOLD
                + " (예상 합격 후기 = 고유 URL 수 × 표본의 'VALID 이면서 합격' 비율)");
        List<Map<String, Object>> rows = new ArrayList<>();
        for (Candidate c : run.certs) rows.add(run.stats.get(c.name()).toMap(c));
        rep.put("certs", rows);
        rep.put("notes", List.copyOf(run.notes));
        if (run.stopReason != null) rep.put("stopReason", run.stopReason);
        return rep;
    }

    private void writeReport(Run run) throws IOException {
        Map<String, Object> rep = buildReport(run);
        lastReport = rep;
        Files.createDirectories(reportDir);
        String stamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmm"));
        Path json = reportDir.resolve("probe-" + stamp + ".json");
        Path md = reportDir.resolve("probe-" + stamp + ".md");
        Files.writeString(json, objectMapper.writeValueAsString(rep), StandardCharsets.UTF_8);
        Files.writeString(md, toMarkdown(rep), StandardCharsets.UTF_8);
        rep.put("files", List.of(json.toString(), md.toString()));
    }

    @SuppressWarnings("unchecked")
    static String toMarkdown(Map<String, Object> rep) {
        StringBuilder sb = new StringBuilder();
        sb.append("# 새 자격증 후보 데이터 확보 시험 (").append(rep.get("startedAt")).append(")\n\n");
        sb.append("상태: ").append(rep.get("state")).append(" · 네이버 API 호출 ").append(rep.get("apiCalls")).append("회\n\n");
        sb.append("판정 기준: ").append(rep.get("criteria")).append("\n\n");
        sb.append("| 자격증 | 검색 total 최대(블로그/카페) | 고유 URL(블로그/카페) | 표본 n | 본문 판정 | VALID 비율 | 합격 비율 | 예상 합격 후기(범위) | 판정 |\n");
        sb.append("|---|---|---|---|---|---|---|---|---|\n");
        for (Map<String, Object> r : (List<Map<String, Object>>) rep.get("certs")) {
            sb.append("| ").append(r.get("cert"))
                    .append(" | ").append(r.get("maxTotalBlog")).append(" / ").append(r.get("maxTotalCafe"))
                    .append(" | ").append(r.get("uniqueBlog")).append(" / ").append(r.get("uniqueCafe"))
                    .append(" | ").append(r.get("sampleTarget"))
                    .append(" | ").append(r.get("judged"))
                    .append(" | ").append(r.get("validRate")).append("%")
                    .append(" | ").append(r.get("passRate")).append("%")
                    .append(" | ").append(r.get("expected")).append(" (").append(r.get("expectedLow")).append("~").append(r.get("expectedHigh")).append(")")
                    .append(" | ").append(r.get("verdict")).append(" |\n");
        }
        sb.append("\n");
        for (Map<String, Object> r : (List<Map<String, Object>>) rep.get("certs")) {
            sb.append("## ").append(r.get("cert")).append("\n");
            sb.append("- 블로그만 기준 판정: ").append(r.get("verdictBlogOnly")).append("\n");
            sb.append("- 순수 후기 기준: 판정 ").append(r.get("pureJudged")).append("건 중 합격 VALID ").append(r.get("pureValidPass"))
                    .append(" → 예상 ").append(r.get("expectedPure")).append(" (").append(r.get("expectedPureLow")).append("~")
                    .append(r.get("expectedPureHigh")).append(") ").append(r.get("verdictPure")).append("\n");
            if (r.get("splitMixed") != null) {
                sb.append("- 조건 적용(섞인 글 분리): 섞인 글 ").append(r.get("splitMixed")).append("건(제목 단독 ")
                        .append(r.get("splitTitleOnly")).append(") 중 이 자격증 구간만으로 합격 VALID ").append(r.get("splitValidPass"))
                        .append(" → 순수와 합쳐 예상 ").append(r.get("expectedSplit")).append(" (").append(r.get("expectedSplitLow"))
                        .append("~").append(r.get("expectedSplitHigh")).append(") ").append(r.get("verdictSplit"))
                        .append(" · 구간 탈락 사유: ").append(r.get("splitTopReasons")).append("\n");
            }
            sb.append("- 시험 구분별 예상: ").append(r.get("byExamType")).append("\n");
            sb.append("- 제외 사유 상위: ").append(r.get("topExcludeReasons")).append("\n");
            sb.append("- 섞임(제외 키워드·기존 4종 함께 언급): ").append(r.get("mixed")).append("건\n");
            sb.append("- 검색 상한 도달: ").append(r.get("capped")).append("\n");
            sb.append("- 본문 없음 ").append(r.get("bodyMissing")).append(" · 권한 없음 ").append(r.get("denied"))
                    .append(" · 실패 ").append(r.get("failed")).append(" · 시간 초과 ").append(r.get("timedOut")).append("\n");
            sb.append("- 사례: ").append(r.get("examples")).append("\n\n");
        }
        List<String> notes = (List<String>) rep.get("notes");
        if (notes != null && !notes.isEmpty()) sb.append("메모: ").append(String.join(" / ", notes)).append("\n");
        if (rep.get("stopReason") != null) sb.append("중단 사유: ").append(rep.get("stopReason")).append("\n");
        return sb.toString();
    }

    private static Map<String, Object> message(String state, String msg) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("state", state);
        m.put("message", msg);
        return m;
    }

    // =====================================================================
    // 실행 1회 상태
    // =====================================================================

    static final class Hit {
        final String url;
        final boolean cafe;
        final String title;
        final String desc;
        final LocalDate postedAt;
        boolean mixed;

        Hit(String url, boolean cafe, String title, String desc, LocalDate postedAt) {
            this.url = url;
            this.cafe = cafe;
            this.title = title;
            this.desc = desc;
            this.postedAt = postedAt;
        }
    }

    static final class CertStat {
        final Candidate cert;
        final Map<String, Integer> totals = new ConcurrentHashMap<>();
        final Set<String> seen = ConcurrentHashMap.newKeySet();
        final List<Hit> blogHits = new CopyOnWriteArrayList<>();
        final List<Hit> cafeHits = new CopyOnWriteArrayList<>();
        final AtomicInteger noKeyword = new AtomicInteger(), excludedTitle = new AtomicInteger(),
                bodyMissing = new AtomicInteger(), denied = new AtomicInteger(), failed = new AtomicInteger(),
                timedOut = new AtomicInteger(), cafeSkipped = new AtomicInteger();
        volatile boolean capped;
        volatile int sampleTarget;
        final List<String> excludedExamples = new CopyOnWriteArrayList<>();
        final List<String> timeoutExamples = new CopyOnWriteArrayList<>();
        final List<String> mixedExamples = new CopyOnWriteArrayList<>();
        /** 출처별(blog / cafe) 판정 수, VALID 수, VALID 이면서 합격 수 */
        final Map<String, int[]> bySource = new ConcurrentHashMap<>();
        final Map<String, AtomicInteger> byStatus = new ConcurrentHashMap<>();
        final Map<String, AtomicInteger> reasons = new ConcurrentHashMap<>();
        /** [11-24] 섞이지 않은 글(순수 후기)만: 출처별 판정 수, VALID 이면서 합격 수 */
        final Map<String, int[]> pureBySource = new ConcurrentHashMap<>();
        /** VALID 이면서 합격인 글의 시험 구분별 수 (출처 blog 기준) */
        final Map<String, AtomicInteger> validPassExamType = new ConcurrentHashMap<>();
        final AtomicInteger mixed = new AtomicInteger(), passed = new AtomicInteger(),
                over3y = new AtomicInteger(), noTime = new AtomicInteger();
        /** [11-26] 섞인 글 분리 조건: 출처별 [섞인 글 수, 구간 판정 수, 구간만으로 VALID·합격], 제목 단독 글 수 */
        final Map<String, int[]> splitBySource = new ConcurrentHashMap<>();
        final AtomicInteger splitTitleOnly = new AtomicInteger();
        final Map<String, AtomicInteger> splitReasons = new ConcurrentHashMap<>();

        synchronized void countSplit(boolean cafe, boolean titleOnly, ExtractedReview rs, QualityResult qs) {
            int[] a = splitBySource.computeIfAbsent(cafe ? "cafe" : "blog", k -> new int[3]);
            a[0]++;
            if (titleOnly) splitTitleOnly.incrementAndGet();
            if (rs == null || qs == null) {
                splitReasons.computeIfAbsent("구간 너무 짧음", k -> new AtomicInteger()).incrementAndGet();
                return;
            }
            a[1]++;
            if ("VALID".equals(qs.reviewStatus()) && Boolean.TRUE.equals(rs.passed())) a[2]++;
            else if (qs.excludeReason() != null && !qs.excludeReason().isBlank())
                splitReasons.computeIfAbsent(qs.excludeReason(), k -> new AtomicInteger()).incrementAndGet();
        }

        CertStat(Candidate cert) {
            this.cert = cert;
        }

        synchronized void count(boolean cafe, ExtractedReview r, QualityResult q, boolean isMixed, String url) {
            String src = cafe ? "cafe" : "blog";
            int[] a = bySource.computeIfAbsent(src, k -> new int[3]);
            a[0]++;
            boolean valid = "VALID".equals(q.reviewStatus());
            boolean pass = Boolean.TRUE.equals(r.passed());
            if (pass) passed.incrementAndGet();
            if (valid) a[1]++;
            if (valid && pass) {
                a[2]++;
                if (!cafe) validPassExamType.computeIfAbsent(r.examType() == null ? "구분 없음" : r.examType().name(),
                        k -> new AtomicInteger()).incrementAndGet();
            }
            byStatus.computeIfAbsent(q.reviewStatus(), k -> new AtomicInteger()).incrementAndGet();
            if (q.excludeReason() != null && !q.excludeReason().isBlank()) {
                reasons.computeIfAbsent(q.excludeReason(), k -> new AtomicInteger()).incrementAndGet();
                if (q.excludeReason().contains("3년")) over3y.incrementAndGet();
                if (q.excludeReason().contains("시간 정보 없음")) noTime.incrementAndGet();
            }
            if (!isMixed) {
                int[] pa = pureBySource.computeIfAbsent(src, k -> new int[2]);
                pa[0]++;
                if (valid && pass) pa[1]++;
            }
            if (isMixed) {
                mixed.incrementAndGet();
                if (mixedExamples.size() < 3) mixedExamples.add(q.reviewStatus() + " | " + url);
            }
        }

        synchronized Map<String, Object> toMap(Candidate c) {
            Map<String, Object> m = new LinkedHashMap<>();
            int[] blog = bySource.getOrDefault("blog", new int[3]);
            int[] cafe = bySource.getOrDefault("cafe", new int[3]);
            int judged = blog[0] + cafe[0];
            m.put("cert", c.name());
            m.put("maxTotalBlog", maxTotal("blog"));
            m.put("maxTotalCafe", maxTotal("cafearticle"));
            m.put("totals", new LinkedHashMap<>(totals));
            m.put("uniqueBlog", blogHits.size());
            m.put("uniqueCafe", cafeHits.size());
            m.put("filteredNoKeyword", noKeyword.get());
            m.put("filteredExcludedTitle", excludedTitle.get());
            m.put("capped", capped ? "예 (검색어당 최대 약 1,100건만 받음 → 예상치는 최소값)" : "아니오");
            m.put("sampleTarget", sampleTarget);
            m.put("judged", judged);
            m.put("judgedBlog", blog[0]);
            m.put("judgedCafe", cafe[0]);
            m.put("validRate", pct(blog[1] + cafe[1], judged));
            m.put("passRate", pct(passed.get(), judged));
            m.put("validPassRateBlog", pct(blog[2], blog[0]));
            m.put("validPassRateCafe", cafe[0] >= 20 ? pct(cafe[2], cafe[0]) : "표본 20건 미만");
            // 예상치: 블로그 비율 × 블로그 고유 URL (+ 카페 표본이 20건 이상이면 카페도 더함)
            long[] eb = estimate(blogHits.size(), blog[2], blog[0]);
            long[] ec = cafe[0] >= 20 ? estimate(cafeHits.size(), cafe[2], cafe[0]) : new long[]{0, 0, 0};
            m.put("expectedBlog", eb[0]);
            m.put("expectedCafe", cafe[0] >= 20 ? ec[0] : "계산 안 함 (카페 표본 부족)");
            long exp = eb[0] + ec[0];
            m.put("expected", exp);
            m.put("expectedLow", eb[1] + ec[1]);
            m.put("expectedHigh", eb[2] + ec[2]);
            m.put("verdict", verdict(exp) + (capped ? " (최소값 기준)" : ""));
            // [11-24] 블로그만 기준 판정 (카페 표본이 작을 때 판정이 카페에 기대지 않도록)
            m.put("verdictBlogOnly", verdict(eb[0]) + " (" + eb[0] + ", " + eb[1] + "~" + eb[2] + ")");
            // [11-24] 순수 후기 기준: 고유 URL × (섞이지 않으면서 VALID·합격인 글 / 판정한 글)
            int[] pb = pureBySource.getOrDefault("blog", new int[2]);
            int[] pc = pureBySource.getOrDefault("cafe", new int[2]);
            m.put("pureJudged", pb[0] + pc[0]);
            m.put("pureValidPass", pb[1] + pc[1]);
            long[] pe = estimate(blogHits.size(), pb[1], blog[0]);
            long[] pce = cafe[0] >= 20 ? estimate(cafeHits.size(), pc[1], cafe[0]) : new long[]{0, 0, 0};
            long pureExp = pe[0] + pce[0];
            m.put("expectedPure", pureExp);
            m.put("expectedPureLow", pe[1] + pce[1]);
            m.put("expectedPureHigh", pe[2] + pce[2]);
            m.put("verdictPure", verdict(pureExp));
            // [11-26] 조건 적용(섞인 글 분리): 순수 후기 + 섞인 글 중 이 자격증 구간만으로 VALID·합격인 글
            int[] sbB = splitBySource.getOrDefault("blog", new int[3]);
            int[] sbC = splitBySource.getOrDefault("cafe", new int[3]);
            long[] se = estimate(blogHits.size(), pb[1] + sbB[2], blog[0]);
            long[] sce = cafe[0] >= 20 ? estimate(cafeHits.size(), pc[1] + sbC[2], cafe[0]) : new long[]{0, 0, 0};
            long splitExp = se[0] + sce[0];
            m.put("splitMixed", sbB[0] + sbC[0]);
            m.put("splitTitleOnly", splitTitleOnly.get());
            m.put("splitJudged", sbB[1] + sbC[1]);
            m.put("splitValidPass", sbB[2] + sbC[2]);
            m.put("expectedSplit", splitExp);
            m.put("expectedSplitLow", se[1] + sce[1]);
            m.put("expectedSplitHigh", se[2] + sce[2]);
            m.put("verdictSplit", verdict(splitExp));
            m.put("splitTopReasons", top(splitReasons, 4));
            Map<String, Object> byExam = new LinkedHashMap<>();
            for (Map.Entry<String, AtomicInteger> e : validPassExamType.entrySet()) {
                long v = blog[0] == 0 ? 0 : Math.round((double) blogHits.size() * e.getValue().get() / blog[0]);
                byExam.put(e.getKey(), v + (!c.writtenOnly() && v < EXAM_TYPE_WARN ? " (100건 미만)" : ""));
            }
            m.put("byExamType", byExam);
            m.put("byStatus", toCounts(byStatus));
            m.put("topExcludeReasons", top(reasons, 5));
            m.put("over3yRate", pct(over3y.get(), judged));
            m.put("noTimeRate", pct(noTime.get(), judged));
            m.put("mixed", mixed.get());
            m.put("bodyMissing", bodyMissing.get());
            m.put("denied", denied.get());
            m.put("cafeSkipped", cafeSkipped.get());
            m.put("failed", failed.get());
            m.put("timedOut", timedOut.get());
            Map<String, Object> ex = new LinkedHashMap<>();
            ex.put("제목에 제외 키워드", List.copyOf(excludedExamples));
            ex.put("섞임", List.copyOf(mixedExamples));
            ex.put("시간 초과", List.copyOf(timeoutExamples));
            m.put("examples", ex);
            return m;
        }

        private int maxTotal(String type) {
            int max = 0;
            for (Map.Entry<String, Integer> e : totals.entrySet()) if (e.getKey().startsWith(type + " ")) max = Math.max(max, e.getValue());
            return max;
        }
    }

    static String pct(int a, int b) {
        return b == 0 ? "0.0" : String.format(Locale.ROOT, "%.1f", 100.0 * a / b);
    }

    private static Map<String, Integer> toCounts(Map<String, AtomicInteger> m) {
        Map<String, Integer> out = new LinkedHashMap<>();
        m.forEach((k, v) -> out.put(k, v.get()));
        return out;
    }

    private static List<String> top(Map<String, AtomicInteger> m, int n) {
        return m.entrySet().stream()
                .sorted((x, y) -> Integer.compare(y.getValue().get(), x.getValue().get()))
                .limit(n).map(e -> e.getKey() + " " + e.getValue().get()).toList();
    }

    private static final class Run {
        final List<Candidate> certs;
        final int sample;
        final int cafeSample;
        final List<String> suffixes = new ArrayList<>(QUERY_SUFFIX);
        final Map<String, CertStat> stats = new LinkedHashMap<>();
        final Instant startedAt = Instant.now();
        final AtomicInteger apiCalls = new AtomicInteger(), done = new AtomicInteger();
        final List<Long> elapsedPerItemMs = new CopyOnWriteArrayList<>();
        final List<String> notes = new CopyOnWriteArrayList<>();
        volatile String state = "RUNNING";
        volatile String phase;
        volatile boolean cancelled;
        volatile String stopReason;
        volatile Instant finishedAt;
        volatile boolean reported;
        private ExecutorService judge = newJudge();
        private int abandoned;

        Run(List<Candidate> certs, int sample, int cafeSample) {
            this.certs = certs;
            this.sample = sample;
            this.cafeSample = cafeSample;
            for (Candidate c : certs) stats.put(c.name(), new CertStat(c));
        }

        private static ExecutorService newJudge() {
            return Executors.newSingleThreadExecutor(r -> {
                Thread t = new Thread(r, "candidate-probe-judge");
                t.setDaemon(true);
                return t;
            });
        }

        synchronized ExecutorService judgeExecutor() {
            return judge;
        }

        /** 시간 초과로 끝나지 않는 스레드는 버리고 새 판정 스레드를 만든다 (버린 스레드 수는 메모에 남긴다) */
        synchronized void replaceJudgeExecutor() {
            judge.shutdownNow();
            judge = newJudge();
            abandoned++;
            notes.removeIf(n -> n.startsWith("시간 초과로 버린 판정 스레드"));
            notes.add("시간 초과로 버린 판정 스레드 " + abandoned + "개 (CPU 를 계속 쓸 수 있으니 실행 후 서버 재시작 권장)");
        }

        synchronized void shutdownJudge() {
            judge.shutdownNow();
        }

        void finish(String s) {
            finishedAt = Instant.now();
            state = s;
        }

        Map<String, Object> status() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("state", state);
            m.put("phase", phase);
            m.put("apiCalls", apiCalls.get());
            int target = 0;
            List<Map<String, Object>> per = new ArrayList<>();
            for (Candidate c : certs) {
                CertStat s = stats.get(c.name());
                target += s.sampleTarget;
                Map<String, Object> p = new LinkedHashMap<>();
                int[] blog = s.bySource.getOrDefault("blog", new int[3]);
                int[] cafe = s.bySource.getOrDefault("cafe", new int[3]);
                p.put("cert", c.name());
                p.put("uniqueBlog", s.blogHits.size());
                p.put("uniqueCafe", s.cafeHits.size());
                p.put("sampleTarget", s.sampleTarget);
                p.put("judged", blog[0] + cafe[0]);
                p.put("valid", blog[1] + cafe[1]);
                p.put("validPass", blog[2] + cafe[2]);
                p.put("failed", s.failed.get() + s.timedOut.get());
                per.add(p);
            }
            m.put("certs", per);
            m.put("done", done.get());
            m.put("target", target);
            double avg = elapsedPerItemMs.isEmpty() ? 0 : elapsedPerItemMs.stream().mapToLong(Long::longValue).average().orElse(0);
            m.put("etaSeconds", target == 0 ? null : Math.round(avg * Math.max(0, target - done.get()) / 1000.0));
            Instant end = finishedAt == null ? Instant.now() : finishedAt;
            m.put("startedAt", startedAt.toString());
            m.put("elapsedSeconds", Duration.between(startedAt, end).toSeconds());
            m.put("notes", List.copyOf(notes));
            if (cancelled) m.put("message", "관리자가 중단했습니다.");
            if (stopReason != null) m.put("stopReason", stopReason);
            return m;
        }
    }

    /** 테스트용: 실행 없이 표본 고르기·집계를 확인한다 */
    static CertStat newStat(Candidate c) {
        return new CertStat(c);
    }

    static Set<String> certNames() {
        return new LinkedHashSet<>(CANDIDATES.keySet());
    }
}
