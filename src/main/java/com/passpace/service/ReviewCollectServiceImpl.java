package com.passpace.service;

import com.passpace.error.exception.CollectException;
import com.passpace.client.ReviewPageFetcher;
import com.passpace.crawler.AuthorHasher;
import com.passpace.crawler.ListingParser;
import com.passpace.crawler.ReviewLinkFilter;
import com.passpace.crawler.ReviewLinkFilter.Candidate;
import com.passpace.crawler.ReviewSite;
import com.passpace.crawler.SourcePermissions;
import com.passpace.crawler.SourcePermissions.Permission;
import com.passpace.crawler.UrlText;
import com.passpace.dto.collect.CollectDtos.CandidateView;
import com.passpace.dto.collect.CollectDtos.CollectJobStatus;
import com.passpace.dto.collect.CollectDtos.CollectResult;
import com.passpace.dto.collect.CollectDtos.DiscoverReport;
import com.passpace.dto.collect.CollectDtos.FetchedPage;
import com.passpace.dto.collect.CollectDtos.PreviewReport;
import com.passpace.dto.collect.CollectDtos.ResetReport;
import com.passpace.dto.collect.CollectDtos.ListingInspect;
import com.passpace.constant.CollectSources;
import com.passpace.dto.collect.CollectDtos.QualityResult;
import com.passpace.service.ReviewQualityChecker.PageContext;
import com.passpace.repository.ExamRoundRepository;
import com.passpace.repository.PassReviewRepository;
import com.passpace.repository.SyncJobRepository;
import com.passpace.crawler.RecoveryReporter;
import com.passpace.crawler.ReviewUrlLedger;
import com.passpace.crawler.SourceRegistry;
import com.passpace.client.TistorySearchBrowser;
import com.passpace.constant.ExamType;
import com.passpace.domain.ExtractedReview;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.EnumMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/**
 * [용성] 후기 수집 흐름 (기획안 7.1 수집 정책)
 *
 *  1. 탐색: collect/review_discovery_sources.txt 의 목록·피드 주소(사람이 고름)를 읽고,
 *          그 안의 링크 중 "허용 사이트의 개별 글 + 자격증·후기 키워드"만 후보로 고른다.
 *          (1단계만. 글 안의 링크를 따라 더 들어가지 않는다)
 *     직접 지정: collect/review_seed_urls.txt 의 글 주소도 후보에 더한다.
 *  2. 사이트별 허용 확인(DATA_SOURCES.permission_checked_at)이 없으면 그 사이트는 건너뜀
 *  3. 이미 저장한 URL·목록 작성일이 3년 지난 글은 건너뛰고, 관리자가 정한 건수(10~1000)만 가져온다
 *     (예전 동기 버튼은 review-max-per-run 건)
 *  4. 글 → 자격증 판단 → 규칙 추출 → 정책 검사(3년·작성일·전재 금지·일정 대조) → 저장
 *     저장 값: 구조화 값 + 요약문 + URL + 작성일 + 작성자 해시 + 수집일 (원문·아이디 저장 안 함)
 *  5. 403·429 는 즉시 전체 중단, robots 금지 경로는 그 주소만 건너뜀
 */
@Service
public class ReviewCollectServiceImpl implements ReviewCollectService {

    private static final Logger log = LoggerFactory.getLogger(ReviewCollectServiceImpl.class);
    static final String DISCOVERY_FILE = "collect/review_discovery_sources.txt";
    static final String SEED_FILE = "collect/review_seed_urls.txt";

    private final ReviewPageFetcher fetcher;
    private final ReviewExtractor extractor;          // 공통 계약 (현재 구현: RuleBasedReviewExtractor)
    private final ReviewQualityChecker qualityChecker;
    private final PassReviewRepository reviewRepository;
    private final ExamRoundRepository examRoundRepository;
    private final SyncJobRepository syncJobRepository;
    private final SourcePermissions permissions;
    private final AuthorHasher authorHasher;
    private final StudyReferenceAggregator referenceAggregator;
    private final ReviewUrlLedger ledger;
    private final RecoveryReporter recoveryReporter;
    private final SourceRegistry sources;
    private final TistorySearchBrowser tistorySearch;
    /** 티스토리 검색어를 마지막으로 검색한 시각 (같은 검색어는 6시간에 한 번만) */
    private final Map<String, Long> searchReadAt = new ConcurrentHashMap<>();
    private static final long SEARCH_TTL_MS = 6L * 60 * 60 * 1000;
    private final int maxPerRun;
    private final int tistoryRssMax;
    /** 티스토리 블로그 RSS 를 마지막으로 읽은 시각 (같은 블로그는 24시간에 한 번만 읽는다) */
    private final Map<String, Long> rssReadAt = new ConcurrentHashMap<>();
    private static final long RSS_TTL_MS = 24L * 60 * 60 * 1000;
    /** 마지막 실행에서 일시적으로 실패한 글 (응답 없음·5xx 등) → '실패분 다시 시도' 대상 */
    private volatile List<Candidate> lastFailed = List.of();

    /** 이번 서버 실행 중 "대상 자격증 아님"으로 판단한 URL (다시 가져오지 않음, DB 에도 저장 안 함) */
    private final Set<String> notTargetUrls = ConcurrentHashMap.newKeySet();

    public ReviewCollectServiceImpl(ReviewPageFetcher fetcher, ReviewExtractor extractor,
                                    ReviewQualityChecker qualityChecker, PassReviewRepository reviewRepository,
                                    ExamRoundRepository examRoundRepository, SyncJobRepository syncJobRepository,
                                    SourcePermissions permissions, AuthorHasher authorHasher,
                                    StudyReferenceAggregator referenceAggregator,
                                    ReviewUrlLedger ledger, RecoveryReporter recoveryReporter, SourceRegistry sources,
                                    TistorySearchBrowser tistorySearch,
                                    @Value("${passpace.collect.review-max-per-run:20}") int maxPerRun,
                                    @Value("${passpace.collect.tistory-rss-max:400}") int tistoryRssMax) {
        this.fetcher = fetcher;
        this.extractor = extractor;
        this.qualityChecker = qualityChecker;
        this.reviewRepository = reviewRepository;
        this.examRoundRepository = examRoundRepository;
        this.syncJobRepository = syncJobRepository;
        this.permissions = permissions;
        this.authorHasher = authorHasher;
        this.referenceAggregator = referenceAggregator;
        this.ledger = ledger;
        this.recoveryReporter = recoveryReporter;
        this.sources = sources;
        this.tistorySearch = tistorySearch;
        this.tistoryRssMax = tistoryRssMax;
        this.maxPerRun = maxPerRun;
    }

    // =====================================================================
    // 1) 수집 실행
    //    [4차 수정] 버튼 한 번으로 목표 건수까지 백그라운드 실행 + 진행률 조회 + 중단.
    //    velog·티스토리를 사이트별 작업자 1개씩 동시에 처리한다 (사이트 안에서는 한 건씩, 간격은 Fetcher 가 지킴).
    //    목록은 실행마다 한 번만 읽고, 목록 작성일이 3년보다 오래된 글은 가져오지 않는다.
    // =====================================================================

    static final int MIN_LIMIT = 10;
    static final int MAX_LIMIT = 1000;

    /** 지금(또는 마지막) 실행 */
    private final AtomicReference<Run> current = new AtomicReference<>();

    /** 예전 버튼(동기 실행, review-max-per-run 건). 화면은 startCollect 를 쓴다 */
    @Override
    public CollectResult collectReviews() {
        Run run = new Run(maxPerRun, null, MODE_NEW, false, false);
        if (!tryStart(run)) {
            return new CollectResult("REVIEW_DISCOVER", "CRAWL", 0, 0, 0, "BUSY", "이미 후기 수집이 실행 중입니다.");
        }
        run.finish(execute(run));
        lastFailed = new ArrayList<>(run.failedUrls);
        return run.toResult();
    }

    static final String MODE_NEW = "NEW";          // 탐색 + 직접 지정 + 수집 이력 중 새 글
    static final String MODE_RECOVER = "RECOVER";  // 수집 이력에서 한 번이라도 저장했던 글만 (목록 탐색 안 함)
    static final String MODE_RETRY = "RETRY";      // 마지막 실행의 일시 실패 글만

    @Override
    public CollectJobStatus startCollect(int limit, String site, String mode, boolean tistoryRss, boolean tistorySearchOn) {
        String m = MODE_RECOVER.equalsIgnoreCase(mode) ? MODE_RECOVER : MODE_RETRY.equalsIgnoreCase(mode) ? MODE_RETRY : MODE_NEW;
        int target = MODE_NEW.equals(m) ? Math.max(MIN_LIMIT, Math.min(MAX_LIMIT, limit)) : Integer.MAX_VALUE;
        Run run = new Run(target, parseSite(site), m, tistoryRss && MODE_NEW.equals(m), tistorySearchOn && MODE_NEW.equals(m));
        if (!tryStart(run)) {
            Run cur = current.get();
            return cur != null && "RUNNING".equals(cur.state) ? cur.status()
                    : new CollectJobStatus("IDLE", "ALL", 0, 0, 0, 0, 0, 0, 0, 0, Map.of(), null, 0,
                    "초기화 중이라 수집을 시작하지 않았습니다. 잠시 뒤 다시 누르세요.", m, lastFailed.size(), null);
        }
        Thread t = new Thread(() -> {
            String state = "DONE";
            try {
                state = execute(run);
            } catch (Exception e) {
                state = "STOPPED";
                run.stopReason = "예상하지 못한 오류: " + e.getMessage();
                log.warn("후기 수집 실행 오류", e);
            } finally {
                lastFailed = new ArrayList<>(run.failedUrls);
                if (MODE_RECOVER.equals(run.mode) || MODE_RETRY.equals(run.mode)) {
                    try {
                        run.notes.add(0, "[복구 리포트] " + recoveryReporter.report().message());
                    } catch (Exception e) {
                        run.notes.add("복구 리포트 실패: " + e.getMessage());
                    }
                }
                try {
                    referenceAggregator.refreshAll();
                    run.notes.add("참고 학습시간 자동 집계 완료");
                } catch (Exception e) {
                    run.notes.add("참고 학습시간 자동 집계 실패: " + e.getMessage());
                }
                run.finish(state);
            }
        }, "review-collect-job");
        t.setDaemon(true);
        t.start();
        return run.status();
    }

    @Override
    public CollectJobStatus jobStatus() {
        Run run = current.get();
        return run == null ? Run.idle() : run.status();
    }

    @Override
    public CollectJobStatus cancelCollect() {
        Run run = current.get();
        if (run == null) return Run.idle();
        if ("RUNNING".equals(run.state)) run.cancelled = true;
        return run.status();
    }

    /** 초기화 중에는 수집을 시작하지 않는다 */
    private volatile boolean resetting;

    private synchronized boolean beginReset() {
        Run cur = current.get();
        if (resetting || (cur != null && "RUNNING".equals(cur.state))) return false;
        resetting = true;
        return true;
    }

    private synchronized boolean tryStart(Run run) {
        Run cur = current.get();
        if (resetting || (cur != null && "RUNNING".equals(cur.state))) return false;
        current.set(run);
        return true;
    }

    private static ReviewSite parseSite(String site) {
        if (site == null || site.isBlank() || "ALL".equalsIgnoreCase(site)) return null;
        try {
            return ReviewSite.valueOf(site.trim().toUpperCase());
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    /**
     * [5차 수정] 후보 찾기와 글 수집을 동시에 한다 (파이프라인).
     *  - 이미 아는 글(등록된 글 주소·수집 이력)은 네트워크 없이 바로 대기열에 넣어 누르자마자 수집을 시작한다
     *  - velog 목록 읽기와 티스토리 RSS 읽기는 각각 별도 스레드에서 동시에 하고, 찾는 대로 대기열에 더한다
     *  - 목록 결과는 1시간 저장해 다시 누르면 목록을 다시 읽지 않는다
     *  - 사이트 작업자(velog 1·티스토리 1)는 대기열에서 한 건씩 꺼내 처리한다 (사이트 안에서는 동시 요청 없음)
     */
    private String execute(Run run) {
        try {
            int imported = ledger.importSaved(reviewRepository.listBySources(
                    List.of(CollectSources.VELOG_REVIEW, CollectSources.TISTORY_REVIEW)));
            if (imported > 0) run.notes.add("DB 에 있던 크롤링 후기 " + imported + "건을 수집 이력에 맞춰 넣음");
        } catch (Exception e) {
            run.notes.add("수집 이력 맞추기 실패: " + e.getMessage());
        }

        // 사이트별 허용 확인 → 대기열 준비
        Map<ReviewSite, Long> sourceIds = new EnumMap<>(ReviewSite.class);
        for (ReviewSite site : ReviewSite.values()) {
            if (run.only != null && site != run.only) continue;
            Permission p = permissions.check(site);
            if (!p.allowed()) {
                run.notes.add(p.reason());
                continue;
            }
            sourceIds.put(site, p.sourceId());
            run.queues.put(site, new LinkedBlockingQueue<>());
            run.discovering.put(site, new java.util.concurrent.atomic.AtomicBoolean(false));
        }
        if (run.queues.isEmpty()) {
            run.notes.add(0, "수집이 허용된 사이트가 없습니다 (DATA_SOURCES.permission_checked_at 확인).");
            return "DONE";
        }

        List<Thread> finders = new ArrayList<>();
        if (MODE_NEW.equals(run.mode)) {
            // 1) 이미 아는 글: 네트워크 없이 바로
            for (String raw : sources.seeds()) {
                String url = UrlText.canonical(raw);
                ReviewSite.of(url).filter(s -> s.isPostUrl(url))
                        .ifPresent(s -> offer(run, new Candidate(url, s, "직접 지정", null)));
            }
            for (ReviewUrlLedger.Entry e : ledger.everSaved()) {
                ReviewSite.of(e.url()).filter(s -> s.isPostUrl(e.url()))
                        .ifPresent(s -> offer(run, new Candidate(e.url(), s, "수집 이력", null)));
            }
            run.notes.add("이미 아는 글에서 바로 시작한 후보 " + run.candidates.get() + "건");
            // 2) 목록·RSS 는 사이트별 스레드에서 동시에
            if (run.queues.containsKey(ReviewSite.VELOG)) {
                finders.add(startFinder(run, ReviewSite.VELOG, () -> findVelog(run)));
            }
            if (run.queues.containsKey(ReviewSite.TISTORY)) {
                finders.add(startFinder(run, ReviewSite.TISTORY, () -> findTistory(run)));
            }
        } else {
            Gathered g = gather(run.mode, run);
            run.notes.addAll(g.messages);
            g.candidates.forEach(c -> offer(run, c));
        }

        ExecutorService pool = Executors.newFixedThreadPool(run.queues.size());
        for (ReviewSite site : run.queues.keySet()) {
            pool.submit(() -> work(run, site, sourceIds.get(site)));
        }
        pool.shutdown();
        try {
            while (!pool.awaitTermination(5, TimeUnit.SECONDS)) {
                // 작업자가 끝날 때까지 기다림 (중단 요청은 작업자가 글 1건마다 확인)
            }
            run.targetReached = true;          // 후보 찾기 스레드도 정리
            for (Thread t : finders) t.join(60_000);
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
            run.cancelled = true;
        }

        for (Counter cnt : run.bySite.values()) {
            String status = cnt.failed.get() == 0 ? "SUCCESS" : (cnt.success.get() > 0 ? "PARTIAL" : "FAILED");
            syncJobRepository.finish(cnt.jobId, cnt.success.get(), cnt.failed.get(), cnt.skipped.get(),
                    status, cnt.failType, cnt.error);
        }
        if (run.candidates.get() == 0) run.notes.add(0, "새로 가져올 후기 글이 없습니다.");
        if (run.stopReason != null) return "STOPPED";
        if (!run.stoppedSites.isEmpty() && run.stoppedSites.keySet().containsAll(run.queues.keySet())) return "STOPPED";
        if (run.cancelled) return "CANCELLED";
        return "DONE";
    }

    /** 후보 1건을 걸러서 사이트 대기열에 넣는다 (중복·이미 저장·대상 아님·3년 지난 글 제외) */
    private boolean offer(Run run, Candidate c) {
        java.util.concurrent.BlockingQueue<Candidate> q = run.queues.get(c.site());
        if (q == null || !run.seen.add(c.url())) return false;
        if (notTargetUrls.contains(c.url()) || reviewRepository.existsByUrl(c.url())) {
            run.alreadySaved.incrementAndGet();
            return false;
        }
        LocalDate cutoff = LocalDate.now().minusYears(ReviewQualityChecker.MAX_AGE_YEARS);
        if (c.listedDate() != null && c.listedDate().isBefore(cutoff)) {
            run.oldSkipped.incrementAndGet();         // 목록에 적힌 작성일이 3년보다 오래됨 → 요청하지 않음
            notTargetUrls.add(c.url());
            return false;
        }
        q.add(c);
        run.candidates.incrementAndGet();
        return true;
    }

    private Thread startFinder(Run run, ReviewSite site, Runnable body) {
        run.discovering.get(site).set(true);
        Thread t = new Thread(() -> {
            try {
                body.run();
            } catch (Exception e) {
                run.notes.add(site + " 후보 찾기 오류: " + e.getMessage());
                log.warn("{} 후보 찾기 오류", site, e);
            } finally {
                run.discovering.get(site).set(false);
            }
        }, "review-find-" + site.name().toLowerCase());
        t.setDaemon(true);
        t.start();
        return t;
    }

    private boolean finderShouldStop(Run run) {
        return run.cancelled || run.stopReason != null || run.targetReached;
    }

    private boolean finderShouldStop(Run run, ReviewSite site) {
        return finderShouldStop(run) || run.stoppedSites.containsKey(site);
    }

    /** velog 목록(검색어·태그) 읽기 */
    private void findVelog(Run run) {
        List<String> lists = sources.listings().stream()
                .filter(u -> ReviewSite.of(u).orElse(null) == ReviewSite.VELOG).toList();
        int i = 0, ok = 0, fail = 0, cached = 0, found = 0;
        for (String listing : lists) {
            if (finderShouldStop(run, ReviewSite.VELOG)) break;
            run.velogPhase = "velog 목록 " + (++i) + "/" + lists.size();
            ListingRead r = readListing(listing, ReviewSite.VELOG);
            if (r.cached) cached++;
            if (r.error != null) {
                fail++;
                if (r.stop) {
                    run.stoppedSites.putIfAbsent(ReviewSite.VELOG, "velog 목록 읽기 중 접근 제한(" + r.error + ")");
                    break;
                }
                continue;
            }
            ok++;
            for (Candidate c : r.candidates) if (offer(run, c)) found++;
        }
        run.velogPhase = null;
        run.notes.add("velog 목록 " + ok + "개 읽음(1시간 안에 읽은 목록 " + cached + "개는 저장된 결과 사용)"
                + (fail > 0 ? ", 실패 " + fail + "개" : "") + " → 새 후보 " + found + "건");
    }

    /** 티스토리: 등록된 RSS + (켜면) 아는 블로그 RSS 자동 확장 */
    private void findTistory(Run run) {
        if (run.tistorySearch) findTistoryBySearch(run);
        Set<String> hosts = new java.util.LinkedHashSet<>();
        List<String> manual = sources.listings().stream()
                .filter(u -> ReviewSite.of(u).orElse(null) == ReviewSite.TISTORY).toList();
        if (run.tistoryRss) {
            for (String u : sources.seeds()) hostOf(u).ifPresent(hosts::add);
            for (ReviewUrlLedger.Entry e : ledger.everSaved()) if (e.url().contains(".tistory.com")) hostOf(e.url()).ifPresent(hosts::add);
            for (String u : manual) hostOf(u).ifPresent(hosts::remove);
        }
        long now = System.currentTimeMillis();
        List<String> rssList = new ArrayList<>(manual);
        int skippedRecent = 0;
        for (String h : hosts) {
            if (rssList.size() - manual.size() >= tistoryRssMax) break;
            if (now - rssReadAt.getOrDefault(h, 0L) <= RSS_TTL_MS) {
                skippedRecent++;
                continue;
            }
            rssList.add("https://" + h + "/rss");
        }
        int i = 0, ok = 0, fail = 0, found = 0;
        for (String rss : rssList) {
            if (finderShouldStop(run, ReviewSite.TISTORY)) break;
            run.tistoryPhase = "티스토리 RSS " + (++i) + "/" + rssList.size();
            ListingRead r = readListing(rss, ReviewSite.TISTORY);
            hostOf(rss).ifPresent(h -> rssReadAt.put(h, System.currentTimeMillis()));
            if (r.error != null) {
                fail++;
                if (r.stop) {
                    run.stoppedSites.putIfAbsent(ReviewSite.TISTORY, "티스토리 RSS 읽기 중 접근 제한(" + r.error + ")");
                    break;
                }
                continue;
            }
            ok++;
            for (Candidate c : r.candidates) if (offer(run, c)) found++;
        }
        run.tistoryPhase = null;
        if (!rssList.isEmpty() || skippedRecent > 0) {
            run.notes.add("티스토리 RSS " + ok + "개 읽음" + (fail > 0 ? ", 실패 " + fail + "개" : "")
                    + (skippedRecent > 0 ? ", 24시간 안에 읽은 블로그 " + skippedRecent + "개는 건너뜀" : "")
                    + " → 새 후보 " + found + "건");
        }
    }

    /** 티스토리 통합 검색 화면에서 새 블로그 글 찾기 (같은 검색어는 6시간에 한 번) */
    private void findTistoryBySearch(Run run) {
        long now = System.currentTimeMillis();
        List<String> keywords = sources.tistoryKeywords().stream()
                .filter(k -> now - searchReadAt.getOrDefault(k, 0L) > SEARCH_TTL_MS).toList();
        int skipped = sources.tistoryKeywords().size() - keywords.size();
        if (keywords.isEmpty()) {
            if (skipped > 0) run.notes.add("티스토리 검색어 " + skipped + "개는 6시간 안에 검색해서 건너뜀");
            return;
        }
        int[] found = {0};
        int pages = tistorySearch.searchAll(keywords,
                links -> {
                    for (Candidate c : ReviewLinkFilter.filter(links)) {
                        if (c.site() != ReviewSite.TISTORY) continue;
                        ledger.found(c.url(), c.site().name());
                        if (offer(run, c)) found[0]++;
                    }
                },
                phase -> run.tistoryPhase = phase,
                () -> finderShouldStop(run, ReviewSite.TISTORY));
        String why = tistorySearch.unavailableReason();
        if (why != null) {
            run.notes.add("티스토리 검색 사용 안 함: " + why);
            return;
        }
        keywords.forEach(k -> searchReadAt.put(k, System.currentTimeMillis()));
        run.notes.add("티스토리 검색어 " + keywords.size() + "개 · " + pages + "쪽 읽음 → 새 후보 " + found[0] + "건"
                + (skipped > 0 ? " (6시간 안에 검색한 검색어 " + skipped + "개는 건너뜀)" : ""));
    }

    private static Optional<String> hostOf(String url) {
        try {
            String h = java.net.URI.create(UrlText.toAscii(url)).getHost();
            return h != null && h.endsWith(".tistory.com") ? Optional.of(h.toLowerCase()) : Optional.empty();
        } catch (IllegalArgumentException e) {
            return Optional.empty();
        }
    }

    /** 목록 1개 읽기 결과 (1시간 저장) */
    private record ListingRead(List<Candidate> candidates, String error, boolean stop, boolean cached) {
    }

    private record CachedListing(long at, List<Candidate> candidates) {
    }

    private static final long LISTING_TTL_MS = 60L * 60 * 1000;
    private final Map<String, CachedListing> listingCache = new ConcurrentHashMap<>();

    private ListingRead readListing(String listing, ReviewSite site) {
        CachedListing c = listingCache.get(listing);
        if (c != null && System.currentTimeMillis() - c.at() < LISTING_TTL_MS) {
            return new ListingRead(c.candidates(), null, false, true);
        }
        try {
            var links = ListingParser.parse(fetcher.fetchListingQuick(listing), UrlText.toAscii(listing));
            List<Candidate> found = ReviewLinkFilter.filter(links).stream().filter(x -> x.site() == site).toList();
            found.forEach(x -> ledger.found(x.url(), x.site().name()));
            listingCache.put(listing, new CachedListing(System.currentTimeMillis(), found));
            return new ListingRead(found, null, false, false);
        } catch (CollectException e) {
            return new ListingRead(List.of(), e.getFailType(), isStop(e), false);
        }
    }

    /** 사이트 하나의 작업자: 대기열에서 자기 사이트 글을 한 건씩 꺼내 처리 (후보 찾기가 끝나고 대기열이 비면 종료) */
    private void work(Run run, ReviewSite site, Long sourceId) {
        java.util.concurrent.BlockingQueue<Candidate> queue = run.queues.get(site);
        Counter cnt = null;
        while (!run.cancelled && run.stopReason == null && !run.stoppedSites.containsKey(site)) {
            Candidate c;
            try {
                c = queue.poll(500, TimeUnit.MILLISECONDS);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                break;
            }
            if (c == null) {
                if (!run.discovering.get(site).get() && queue.isEmpty()) break;   // 찾기 끝 + 대기열 비어 있음
                continue;
            }
            if (run.claimed.incrementAndGet() > run.target) {   // 목표 건수 도달
                run.targetReached = true;
                break;
            }
            if (cnt == null) {
                try {
                    cnt = new Counter(syncJobRepository.start(sourceId, "REVIEW_DISCOVER"));
                } catch (Exception e) {
                    run.notes.add(site + " 실행 기록 시작 실패: " + e.getMessage());
                    return;
                }
                run.bySite.put(site, cnt);
            }
            try {
                Analysis a = analyze(c.url(), c.site(), sourceId, c.listedDate());
                if (a.skipReason() != null) {
                    cnt.skipped.incrementAndGet();
                    notTargetUrls.add(c.url());
                    ledger.record(c.url(), site.name(), "SKIP");
                    log.info("저장 안 함 {} ({})", c.url(), a.skipReason());
                } else {
                    reviewRepository.insert(a.sourceId(), a.certId(), a.url(), a.postedAt(), a.authorHash(), a.review(), a.quality());
                    ledger.record(c.url(), site.name(), "SAVED:" + a.quality().reviewStatus());
                    cnt.success.incrementAndGet();
                    if ("VALID".equals(a.quality().reviewStatus())) cnt.valid.incrementAndGet();
                    log.info("후기 저장 [{}] {} ({})", a.quality().reviewStatus(), a.url(),
                            a.quality().excludeReason() == null ? "통계 사용" : a.quality().excludeReason());
                }
            } catch (CollectException e) {
                cnt.failed.incrementAndGet();
                cnt.failType = e.getFailType();
                cnt.error = e.getMessage();
                ledger.record(c.url(), site.name(), "FAIL:" + e.getFailType());
                if (!isPermanent(e)) run.failedUrls.add(c);       // 응답 없음·5xx·403/429 → 나중에 다시 시도 가능
                if (isStop(e)) {
                    // [7차] 403·429 는 그 사이트만 즉시 중단 (다른 사이트 서버와는 무관하므로 계속 진행)
                    run.stoppedSites.put(site, e.getMessage());
                    log.warn("수집 중단: {}", e.getMessage());
                } else {
                    if (isPermanent(e)) {
                        notTargetUrls.add(c.url());     // 없는 글·로그인 글·robots 금지는 이번 서버 실행 중 다시 요청하지 않음
                    }
                    log.warn("건너뜀: {}", e.getMessage());
                }
            } catch (Exception e) {
                cnt.failed.incrementAndGet();
                cnt.error = e.getMessage();
                ledger.record(c.url(), site.name(), "FAIL:ERROR");
                run.failedUrls.add(c);
                log.warn("후기 처리 실패 {}: {}", c.url(), e.getMessage());
            } finally {
                run.processed.incrementAndGet();
            }
        }
    }

    /** 실행 1회의 상태 (여러 스레드가 함께 씀) */
    private static final class Run {
        final int target;
        final ReviewSite only;
        final String mode;
        final boolean tistoryRss;
        final boolean tistorySearch;
        final Map<ReviewSite, java.util.concurrent.BlockingQueue<Candidate>> queues = new ConcurrentHashMap<>();
        /** 사이트별 후보 찾기가 아직 진행 중인지 */
        final Map<ReviewSite, java.util.concurrent.atomic.AtomicBoolean> discovering = new ConcurrentHashMap<>();
        final Set<String> seen = ConcurrentHashMap.newKeySet();
        volatile String velogPhase, tistoryPhase;
        volatile boolean targetReached;
        final ConcurrentLinkedQueue<Candidate> failedUrls = new ConcurrentLinkedQueue<>();
        final Instant startedAt = Instant.now();
        final AtomicInteger claimed = new AtomicInteger();
        final AtomicInteger processed = new AtomicInteger();
        final AtomicInteger candidates = new AtomicInteger();
        final AtomicInteger alreadySaved = new AtomicInteger();
        final AtomicInteger oldSkipped = new AtomicInteger();
        final Map<ReviewSite, Counter> bySite = new ConcurrentHashMap<>();
        final List<String> notes = new CopyOnWriteArrayList<>();
        volatile String state = "RUNNING";
        volatile Instant finishedAt;
        volatile boolean cancelled;
        volatile String stopReason;
        /** 접근 제한(403·429·쉬는 중)으로 멈춘 사이트와 이유 */
        final Map<ReviewSite, String> stoppedSites = new ConcurrentHashMap<>();

        Run(int target, ReviewSite only, String mode, boolean tistoryRss, boolean tistorySearch) {
            this.target = target;
            this.only = only;
            this.mode = mode;
            this.tistoryRss = tistoryRss;
            this.tistorySearch = tistorySearch;
        }

        /** 지금 하는 일: 후보 찾는 단계(사이트별 n/m)와 글 수집이 동시에 진행될 수 있다 */
        String phase() {
            if (finishedAt != null) return null;
            List<String> parts = new ArrayList<>();
            if (velogPhase != null) parts.add(velogPhase);
            if (tistoryPhase != null) parts.add(tistoryPhase);
            return parts.isEmpty() ? "글 수집 중" : "후보 찾는 중 (" + String.join(" · ", parts) + ") + 글 수집 중";
        }

        /** 화면에 보일 목표: 복구·재시도는 후보 전체 */
        int shownTarget() {
            return target == Integer.MAX_VALUE ? candidates.get() : target;
        }

        void finish(String finalState) {
            finishedAt = Instant.now();
            state = finalState;
        }

        int sum(java.util.function.Function<Counter, AtomicInteger> f) {
            return bySite.values().stream().mapToInt(c -> f.apply(c).get()).sum();
        }

        String message() {
            StringBuilder sb = new StringBuilder();
            if (MODE_NEW.equals(mode) && candidates.get() < target && !"RUNNING".equals(state)) {
                sb.append("후보 부족: 새로 가져올 수 있는 글이 ").append(candidates.get()).append("건뿐이었습니다. ");
            }
            if (alreadySaved.get() > 0) sb.append("이미 저장했거나 대상 아님으로 확인한 글 ").append(alreadySaved.get()).append("건은 다시 요청하지 않음. ");
            if (stopReason != null) sb.append("중단: ").append(stopReason).append(" ");
            stoppedSites.forEach((site, why) -> sb.append(site).append(" 중단(다른 사이트는 계속): ").append(why).append(" "));
            if (cancelled) sb.append("관리자가 중단했습니다. ");
            sb.append("| ").append(String.join(" / ", notes));
            return sb.toString().strip();
        }

        CollectJobStatus status() {
            Map<String, String> sites = new LinkedHashMap<>();
            bySite.forEach((s, c) -> sites.put(s.name(), "저장 " + c.success.get() + "(VALID " + c.valid.get()
                    + "), 건너뜀 " + c.skipped.get() + ", 실패 " + c.failed.get()));
            Instant end = finishedAt == null ? Instant.now() : finishedAt;
            return new CollectJobStatus(state, only == null ? "ALL" : only.name(), shownTarget(), candidates.get(),
                    processed.get(), sum(c -> c.success), sum(c -> c.valid), sum(c -> c.skipped),
                    sum(c -> c.failed), oldSkipped.get(), sites, startedAt.toString(),
                    Duration.between(startedAt, end).toSeconds(), message(), mode, failedUrls.size(), phase());
        }

        static CollectJobStatus idle() {
            return new CollectJobStatus("IDLE", "ALL", 0, 0, 0, 0, 0, 0, 0, 0, Map.of(), null, 0,
                    "이번 서버 실행 중 수집한 적이 없습니다.", MODE_NEW, 0, null);
        }

        CollectResult toResult() {
            int success = sum(c -> c.success), failed = sum(c -> c.failed);
            String status = "STOPPED".equals(state) ? "STOPPED"
                    : success == 0 && failed == 0 ? "SKIPPED"
                    : failed == 0 ? "SUCCESS" : (success > 0 ? "PARTIAL" : "FAILED");
            String msg = "저장 " + success + "건(VALID " + sum(c -> c.valid) + "건 포함), 건너뜀 "
                    + (sum(c -> c.skipped) + alreadySaved.get()) + "건, 실패 " + failed + "건, 3년 지난 글 미리 제외 "
                    + oldSkipped.get() + "건 " + message();
            return new CollectResult("REVIEW_DISCOVER", "CRAWL", success, failed,
                    sum(c -> c.skipped) + alreadySaved.get(), status, msg);
        }
    }

    // =====================================================================
    // 1-2) 크롤링 후기 초기화 (규칙을 고친 뒤 처음부터 다시 판정할 때)
    //      velog(3)·티스토리(7) 출처 후기만 지운다. 더미(4)·시험일정·회원 데이터는 건드리지 않는다.
    // =====================================================================

    @Override
    public ResetReport resetCrawledReviews(boolean execute) {
        int velog = reviewRepository.countBySource(CollectSources.VELOG_REVIEW);
        int tistory = reviewRepository.countBySource(CollectSources.TISTORY_REVIEW);
        if (!execute) {
            return new ResetReport(false, velog, tistory,
                    "삭제 예정: velog " + velog + "건, 티스토리 " + tistory + "건 (더미·시험일정·회원 데이터는 지우지 않음)");
        }
        // 수집과 동시에 지우지 않도록 실행 슬롯을 잡은 상태에서 지운다
        if (!beginReset()) {
            return new ResetReport(false, velog, tistory, "수집이 진행 중이라 초기화하지 않았습니다. 끝난 뒤 다시 시도하세요.");
        }
        try {
            // 복구율 비교 기준: 지우기 직전 상태를 프로젝트 폴더 파일에 남긴다 (주소·판정·구조화 값만)
            var rows = reviewRepository.listBySources(List.of(CollectSources.VELOG_REVIEW, CollectSources.TISTORY_REVIEW));
            ledger.importSaved(rows);          // 이력 파일이 생기기 전에 수집한 글도 복구 대상에 포함
            ledger.writeSnapshot(rows);
            int dv = reviewRepository.deleteBySource(CollectSources.VELOG_REVIEW);
            int dt = reviewRepository.deleteBySource(CollectSources.TISTORY_REVIEW);
            int memo = notTargetUrls.size();
            notTargetUrls.clear();
            String agg;
            try {
                referenceAggregator.refreshAll();
                agg = "참고 학습시간 다시 집계 완료";
            } catch (Exception e) {
                agg = "참고 학습시간 집계 실패: " + e.getMessage();
            }
            log.info("크롤링 후기 초기화: velog {}건, 티스토리 {}건 삭제, 메모리 기록 {}건 비움", dv, dt, memo);
            return new ResetReport(true, dv, dt, "삭제 완료: velog " + dv + "건, 티스토리 " + dt
                    + "건. 서버의 '대상 아님' 기록 " + memo + "건도 비웠습니다. " + agg
                    + ". 지우기 직전 상태를 기록했습니다 → '복구 수집' 후 '복구율 확인'으로 비교할 수 있습니다.");
        } finally {
            resetting = false;
        }
    }

    // =====================================================================
    // 2) 탐색만 (관리자 확인용, 글 페이지는 가져오지 않음)
    // =====================================================================

    @Override
    public DiscoverReport discover() {
        Gathered g = gather(MODE_NEW, null);
        List<CandidateView> views = g.candidates.stream()
                .map(c -> new CandidateView(c.url(), c.site().name(), c.label(), c.listedDate(),
                        reviewRepository.existsByUrl(c.url())))
                .toList();
        return new DiscoverReport(g.messages, views);
    }

    @Override
    public ListingInspect inspectListing(String url) {
        String u = url == null ? "" : url.strip();
        if (u.startsWith(SourceRegistry.TISTORY_SEARCH)) {
            String keyword = u.substring(SourceRegistry.TISTORY_SEARCH.length());
            try {
                var hits = tistorySearch.searchOnce(keyword);
                List<ListingParser.ListingLink> links = hits.stream()
                        .map(h -> new ListingParser.ListingLink(h.url(), h.title(), h.postedAt())).toList();
                List<CandidateView> found = ReviewLinkFilter.filter(links).stream()
                        .map(c -> new CandidateView(c.url(), c.site().name(), c.label(), c.listedDate(),
                                reviewRepository.existsByUrl(c.url())))
                        .toList();
                long saved = found.stream().filter(CandidateView::alreadySaved).count();
                String why = tistorySearch.unavailableReason();
                return new ListingInspect(u, hits.size(), found, why != null ? "티스토리 검색 사용 불가: " + why
                        : "검색 결과 1쪽 " + hits.size() + "개 중 후기 후보 " + found.size() + "개 (이미 저장 " + saved
                        + "개, 새 글 " + (found.size() - saved) + "개). 수집 때는 최대 여러 쪽을 읽습니다.");
            } catch (Exception e) {
                return new ListingInspect(u, 0, List.of(), "티스토리 검색을 열지 못했습니다 (PC 에 크롬 필요): " + e.getMessage());
            }
        }
        Optional<ReviewSite> site = ReviewSite.of(u);
        if (site.isEmpty()) {
            return new ListingInspect(u, 0, List.of(), "velog·티스토리 주소가 아닙니다.");
        }
        Permission p = permissions.check(site.get());
        if (!p.allowed()) {
            return new ListingInspect(u, 0, List.of(), p.reason());
        }
        try {
            var links = ListingParser.parse(fetcher.fetchListing(u), UrlText.toAscii(u));
            List<CandidateView> found = ReviewLinkFilter.filter(links).stream()
                    .filter(c -> c.site() == site.get())
                    .map(c -> new CandidateView(c.url(), c.site().name(), c.label(), c.listedDate(),
                            reviewRepository.existsByUrl(c.url())))
                    .toList();
            long saved = found.stream().filter(CandidateView::alreadySaved).count();
            return new ListingInspect(u, links.size(), found, "링크 " + links.size() + "개 중 후기 후보 " + found.size()
                    + "개 (이미 저장 " + saved + "개, 새 글 " + (found.size() - saved) + "개)");
        } catch (CollectException e) {
            return new ListingInspect(u, 0, List.of(), "목록을 열지 못했습니다: " + e.getFailType() + " " + e.getMessage());
        }
    }

    // =====================================================================
    // 3) 미리보기 (글 1개, 저장 안 함)
    // =====================================================================

    @Override
    public PreviewReport preview(String rawUrl) {
        String url = UrlText.canonical(rawUrl == null ? "" : rawUrl);
        Optional<ReviewSite> site = ReviewSite.of(url);
        if (site.isEmpty() || !site.get().isPostUrl(url)) {
            return new PreviewReport(url, null, "SKIP", null, null, false, null, null,
                    "velog(https://velog.io/@아이디/글주소) 또는 티스토리(https://블로그.tistory.com/번호) 글 주소만 가능합니다.");
        }
        Permission p = permissions.check(site.get());
        if (!p.allowed()) {
            return new PreviewReport(url, site.get().name(), "SKIP", null, null, false, null, null, p.reason());
        }
        try {
            Analysis a = analyze(url, site.get(), p.sourceId(), null);
            if (a.skipReason() != null) {
                return new PreviewReport(url, site.get().name(), "SKIP", a.certCode(), a.postedAt(), false,
                        null, null, a.skipReason());
            }
            boolean saved = reviewRepository.existsByUrl(url);
            return new PreviewReport(url, site.get().name(), "SAVE_" + a.quality().reviewStatus(), a.certCode(),
                    a.postedAt(), a.authorHash() != null, a.review(), a.quality(),
                    (saved ? "이미 저장된 글입니다. " : "") + "미리보기만 했고 저장하지 않았습니다.");
        } catch (CollectException e) {
            return new PreviewReport(url, site.get().name(), "SKIP", null, null, false, null, null,
                    e.getFailType() + ": " + e.getMessage());
        }
    }

    // =====================================================================
    // 글 1개 분석 (수집·미리보기 공통)
    // =====================================================================

    Analysis analyze(String url, ReviewSite site, Long sourceId, LocalDate listedDate) {
        FetchedPage page = fetcher.fetchPost(url, site, authorHasher);
        LocalDate postedAt = page.postedAt() != null ? page.postedAt() : listedDate;   // 피드 작성일로 보충

        Optional<String> code = CertificateDetector.detect(page.title(), page.text());
        if (code.isEmpty()) {
            return Analysis.skip(url, null, postedAt, "대상 자격증(정보처리기사·SQLD) 판단 불가 또는 둘 다 언급");
        }
        Optional<Long> certId = examRoundRepository.findCertificationId(code.get());
        if (certId.isEmpty()) {
            return Analysis.skip(url, code.get(), postedAt, "CERTIFICATIONS 에 " + code.get() + " 없음 (db/03_seed.sql)");
        }

        ExtractedReview review = extractor.extract(page.title(), page.text());
        if ("SQLD".equals(code.get()) && review.examType() != ExamType.WRITTEN) {
            review = RuleBasedReviewExtractor.withExamType(review, ExamType.WRITTEN);   // SQLD 는 시험이 1종류
        }

        LocalDate officialDate = null;
        if (review.examYear() != null && review.roundNo() != null && review.examType() != null) {
            officialDate = examRoundRepository
                    .find(certId.get(), review.examYear(), review.roundNo(), review.examType().name())
                    .map(ExamRoundRepository.StoredRound::examStart).orElse(null);
        }
        QualityResult quality = qualityChecker.check(review, page.text(),
                new PageContext(postedAt, LocalDate.now(), page.noReprint(), officialDate));
        if (page.noReprint()) {
            // 전재 금지 글은 값도 남기지 않는다 (같은 글을 다시 가져오지 않도록 URL·사유만 기록)
            review = new ExtractedReview(null, null, null, null, null, null, null, null, null, null, false, null);
        }
        return new Analysis(url, sourceId, certId.get(), code.get(), postedAt, page.authorHash(), review, quality, null);
    }

    record Analysis(String url, Long sourceId, long certId, String certCode, LocalDate postedAt, String authorHash,
                    ExtractedReview review, QualityResult quality, String skipReason) {
        static Analysis skip(String url, String certCode, LocalDate postedAt, String reason) {
            return new Analysis(url, null, 0, certCode, postedAt, null, null, null, reason);
        }
    }

    // =====================================================================
    // 후보 모으기 (탐색 + 직접 지정)
    // =====================================================================

    private record Gathered(List<Candidate> candidates, List<String> messages, Map<ReviewSite, Long> sourceIds) {
    }

    private Gathered gather(String mode, Run run) {
        List<String> messages = new ArrayList<>();
        Map<String, Candidate> byUrl = new LinkedHashMap<>();
        Map<ReviewSite, Permission> perms = new EnumMap<>(ReviewSite.class);
        Map<ReviewSite, Long> sourceIds = new EnumMap<>(ReviewSite.class);

        if (MODE_RETRY.equals(mode)) {
            for (Candidate c : lastFailed) addKnown(c.url(), "실패분 다시 시도", perms, sourceIds, byUrl, messages);
            messages.add("실패분 다시 시도: " + byUrl.size() + "건");
            return new Gathered(new ArrayList<>(byUrl.values()), messages, sourceIds);
        }
        if (MODE_RECOVER.equals(mode)) {
            for (ReviewUrlLedger.Entry e : ledger.everSaved()) addKnown(e.url(), "수집 이력", perms, sourceIds, byUrl, messages);
            messages.add("복구 수집: 수집 이력(" + ledger.ledgerPath() + ")에서 저장했던 글 " + byUrl.size() + "건");
            return new Gathered(new ArrayList<>(byUrl.values()), messages, sourceIds);
        }

        List<String> listings = sources.listings();
        for (String listing : listings) {
            if (run != null && run.cancelled) break;
            Optional<ReviewSite> site = ReviewSite.of(listing);
            if (site.isEmpty()) {
                messages.add("허용 사이트 아님(velog·티스토리만): " + listing);
                continue;
            }
            Permission p = perms.computeIfAbsent(site.get(), permissions::check);
            if (!p.allowed()) {
                if (!messages.contains(p.reason())) messages.add(p.reason());
                continue;
            }
            sourceIds.put(site.get(), p.sourceId());
            try {
                String body = fetcher.fetchListing(listing);
                var links = ListingParser.parse(body, UrlText.toAscii(listing));
                List<Candidate> found = ReviewLinkFilter.filter(links).stream()
                        .filter(c -> c.site() == site.get()).toList();
                found.forEach(c -> {
                    byUrl.putIfAbsent(c.url(), c);
                    ledger.found(c.url(), c.site().name());
                });
                messages.add("목록 " + listing + " → 링크 " + links.size() + "개 중 후기 후보 " + found.size() + "개");
            } catch (CollectException e) {
                messages.add("목록 실패 " + listing + " (" + e.getFailType() + ")");
                if (isStop(e)) {
                    messages.add("접근 거부로 탐색 중단");
                    break;
                }
            }
        }

        int seeds = 0;
        for (String raw : sources.seeds()) {
            String url = UrlText.canonical(raw);
            Optional<ReviewSite> site = ReviewSite.of(url);
            if (site.isEmpty() || !site.get().isPostUrl(url)) {
                messages.add("직접 지정 주소 형식 오류: " + raw);
                continue;
            }
            Permission p = perms.computeIfAbsent(site.get(), permissions::check);
            if (!p.allowed()) {
                if (!messages.contains(p.reason())) messages.add(p.reason());
                continue;
            }
            sourceIds.put(site.get(), p.sourceId());
            byUrl.putIfAbsent(url, new Candidate(url, site.get(), "직접 지정", null));
            ledger.found(url, site.get().name());
            seeds++;
        }
        // 수집 이력에서 저장했던 글도 후보에 넣는다 (DB 에 없으면 다시 수집 → 일반 수집만으로도 복구됨)
        int fromLedger = 0;
        for (ReviewUrlLedger.Entry e : ledger.everSaved()) {
            if (!byUrl.containsKey(e.url()) && addKnown(e.url(), "수집 이력", perms, sourceIds, byUrl, messages)) fromLedger++;
        }
        if (fromLedger > 0) messages.add("수집 이력에서 추가한 후보 " + fromLedger + "건");

        if (listings.isEmpty() && seeds == 0) {
            messages.add("수집 범위(" + sources.listingPath().getParent() + ")에 주소가 없습니다");
        }
        return new Gathered(new ArrayList<>(byUrl.values()), messages, sourceIds);
    }

    /** 이미 아는 글 주소를 후보에 넣는다 (허용 사이트·글 주소 형식·사이트 허용 확인) */
    private boolean addKnown(String url, String label, Map<ReviewSite, Permission> perms, Map<ReviewSite, Long> sourceIds,
                             Map<String, Candidate> byUrl, List<String> messages) {
        Optional<ReviewSite> site = ReviewSite.of(url);
        if (site.isEmpty() || !site.get().isPostUrl(url)) return false;
        Permission p = perms.computeIfAbsent(site.get(), permissions::check);
        if (!p.allowed()) {
            if (!messages.contains(p.reason())) messages.add(p.reason());
            return false;
        }
        sourceIds.put(site.get(), p.sourceId());
        return byUrl.putIfAbsent(url, new Candidate(url, site.get(), label, null)) == null;
    }

    private static boolean isPermanent(CollectException e) {
        String t = e.getFailType();
        return "HTTP_404".equals(t) || "HTTP_410".equals(t) || "LOGIN_REQUIRED".equals(t)
                || "ROBOTS_DENIED".equals(t) || "PARSE".equals(t);
    }

    private static boolean isStop(CollectException e) {
        return "HTTP_403".equals(e.getFailType()) || "HTTP_429".equals(e.getFailType()) || "COOLDOWN".equals(e.getFailType());
    }

    /** # 으로 시작하는 줄과 빈 줄은 무시 */
    private static List<String> readLines(String classpath) {
        try {
            String content = new ClassPathResource(classpath).getContentAsString(StandardCharsets.UTF_8);
            return content.lines().map(String::strip)
                    .filter(l -> !l.isEmpty() && !l.startsWith("#"))
                    .toList();
        } catch (IOException e) {
            return List.of();
        }
    }

    private static final class Counter {
        final long jobId;
        final AtomicInteger success = new AtomicInteger(), failed = new AtomicInteger(),
                skipped = new AtomicInteger(), valid = new AtomicInteger();
        volatile String failType, error;

        Counter(long jobId) {
            this.jobId = jobId;
        }
    }
}
