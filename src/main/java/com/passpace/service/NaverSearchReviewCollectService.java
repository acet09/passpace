package com.passpace.service;

import com.passpace.client.NaverSearchClient;
import com.passpace.client.NaverSearchClient.Item;
import com.passpace.crawler.SourceRegistry;
import com.passpace.dto.collect.CertCountStatus;
import com.passpace.dto.collect.CollectDtos.CollectJobStatus;
import com.passpace.dto.collect.NaverCollectStatus;
import com.passpace.dto.collect.NaverCollectStatus.NewsItem;
import com.passpace.error.exception.CollectException;
import org.jsoup.Jsoup;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [용성·11-14] 네이버 검색 API 영역 — 블로그·카페 후기(요약문) + 뉴스(참고용)
 *
 *  1. collect-data/naver_keywords.txt 의 검색어마다
 *     블로그·카페 × 정렬(sim·date) × start 1~901(100건씩, 최대 10쪽) 호출
 *  2. 제목 + 요약문만으로 ReviewIngestService 에 넘긴다 → source_id NULL, VALID 로는 저장하지 않음(PENDING/EXCLUDED)
 *     - 블로그: blog.naver.com 글만 (다른 블로그 주소는 크롤링 영역과 겹치므로 건너뜀), postdate → posted_at, 블로거 아이디 → 작성자 해시
 *     - 카페: 작성일·작성자 없음 → posted_at·author_hash NULL
 *  3. 뉴스: 검색어마다 최신순 1쪽 → 화면 참고용 목록(서버 메모리)만, DB 저장 안 함
 *  4. DATA_SYNC_JOBS 에는 기록하지 않는다 (source_id NOT NULL 이고 DATA_SOURCES 행을 추가하지 않기 때문) → 화면 상태·로그만
 *  5. 크롤링 영역과 동시에 실행하지 않는다. 끝나면 참고 학습시간 자동 재집계 1회
 */
@Service
public class NaverSearchReviewCollectService {

    private static final Logger log = LoggerFactory.getLogger(NaverSearchReviewCollectService.class);
    private static final int DISPLAY = 100;
    private static final int MAX_START = 1000;
    private static final int NEWS_KEEP = 100;
    private static final List<String> REVIEW_TYPES = List.of("blog", "cafearticle");
    private static final List<String> SORTS = List.of("sim", "date");

    /** blog.naver.com/아이디/글번호 · m.blog.naver.com/아이디/글번호 */
    private static final Pattern BLOG_PATH = Pattern.compile("^https?://(?:m\\.)?blog\\.naver\\.com/([A-Za-z0-9_\\-]+)/(\\d+)");
    /** blog.naver.com/PostView.naver?blogId=아이디&logNo=글번호 */
    private static final Pattern BLOG_ID = Pattern.compile("[?&]blogId=([A-Za-z0-9_\\-]+)");
    private static final Pattern LOG_NO = Pattern.compile("[?&]logNo=(\\d+)");
    private static final Pattern BLOGGER = Pattern.compile("blog\\.naver\\.com/([A-Za-z0-9_\\-]+)");

    private final NaverSearchClient client;
    private final ReviewIngestService ingest;
    private final SourceRegistry sources;
    private final ReviewCollectService crawlService;
    private final CollectRunGuard runGuard;
    private final StudyReferenceAggregator referenceAggregator;

    private final AtomicReference<Run> current = new AtomicReference<>();
    /** 최근 뉴스 (링크 기준 중복 제거, 최신 NEWS_KEEP 건) */
    private final Map<String, NewsItem> news = new ConcurrentHashMap<>();

    public NaverSearchReviewCollectService(NaverSearchClient client, ReviewIngestService ingest, SourceRegistry sources,
                                           ReviewCollectService crawlService, CollectRunGuard runGuard,
                                           StudyReferenceAggregator referenceAggregator) {
        this.client = client;
        this.ingest = ingest;
        this.sources = sources;
        this.crawlService = crawlService;
        this.runGuard = runGuard;
        this.referenceAggregator = referenceAggregator;
    }

    // =====================================================================
    // 시작 · 상태 · 중단
    // =====================================================================

    public synchronized NaverCollectStatus start() {
        Run cur = current.get();
        if (cur != null && "RUNNING".equals(cur.state)) return status();
        if (!client.hasKey()) {
            return statusWith(Run.message("IDLE", "네이버 검색 API 키 없음: application-local.yml 에 passpace.collect.naver.client-id·client-secret 을 넣으세요. (크롤링 영역은 그대로 동작)"));
        }
        if ("RUNNING".equals(crawlService.jobStatus().state())) {
            return statusWith(Run.message("IDLE", "다른 수집 실행 중(크롤링)이라 네이버 수집을 시작하지 않았습니다. 끝난 뒤 다시 누르세요."));
        }
        List<String> keywords = sources.naverKeywords();
        if (keywords.isEmpty()) {
            return statusWith(Run.message("IDLE", "네이버 검색어가 없습니다. 수집 범위에서 검색어를 추가하세요."));
        }
        if (!runGuard.beginNaver()) return status();
        Run run = new Run(keywords);
        current.set(run);
        Thread t = new Thread(() -> {
            String state = "DONE";
            try {
                state = execute(run);
            } catch (Exception e) {
                state = "STOPPED";
                run.stopReason = "예상하지 못한 오류: " + e.getMessage();
                log.warn("네이버 수집 실행 오류", e);
            } finally {
                try {
                    referenceAggregator.refreshAll();
                    run.notes.add("참고 학습시간 자동 집계 완료");
                } catch (Exception e) {
                    run.notes.add("참고 학습시간 자동 집계 실패: " + e.getMessage());
                }
                run.finish(state);
                runGuard.endNaver();
            }
        }, "naver-collect-job");
        t.setDaemon(true);
        t.start();
        return status();
    }

    public NaverCollectStatus status() {
        Run run = current.get();
        return statusWith(run == null ? Run.message("IDLE", "이번 서버 실행 중 네이버 수집을 한 적이 없습니다.") : run.status());
    }

    public NaverCollectStatus cancel() {
        Run run = current.get();
        if (run != null && "RUNNING".equals(run.state)) run.cancelled = true;
        return status();
    }

    public CertCountStatus certCountStatus() {
        Run run = current.get();
        if (run == null) return new CertCountStatus("NAVER", "IDLE", Map.of());
        return new CertCountStatus("NAVER", run.state, CertCountStatus.from(run.certCounts));
    }

    private NaverCollectStatus statusWith(CollectJobStatus job) {
        List<NewsItem> list = new ArrayList<>(news.values());
        list.sort((a, b) -> b.date().compareTo(a.date()));
        if (list.size() > NEWS_KEEP) list = list.subList(0, NEWS_KEEP);
        return new NaverCollectStatus(job, client.hasKey(), client.usedToday(), client.dailyLimit(), list);
    }

    // =====================================================================
    // 실행
    // =====================================================================

    private String execute(Run run) {
        Set<String> seen = ConcurrentHashMap.newKeySet();      // 같은 실행 안에서 sim·date 정렬로 겹친 주소
        int k = 0;
        outer:
        for (String keyword : run.keywords) {
            k++;
            for (String type : REVIEW_TYPES) {
                for (String sort : SORTS) {
                    for (int start = 1; start <= MAX_START - DISPLAY + 1; start += DISPLAY) {
                        if (run.cancelled) break outer;
                        run.phase = "검색어 " + k + "/" + run.keywords.size() + " · " + label(type) + " · " + sort + " · " + start + "번째부터";
                        NaverSearchClient.Page page;
                        try {
                            page = client.search(type, keyword, sort, start, DISPLAY);
                        } catch (CollectException e) {
                            if (isStop(e)) {
                                run.stopReason = e.getMessage();
                                break outer;
                            }
                            run.failed.incrementAndGet();
                            run.notes.add("호출 실패(" + keyword + " · " + label(type) + "): " + e.getFailType());
                            break;            // 이 정렬은 넘어가고 다음으로
                        }
                        for (Item item : page.items()) handle(run, type, item, seen);
                        if (page.items().size() < DISPLAY || start + DISPLAY > page.total()) break;
                    }
                }
            }
            // 3순위: 뉴스 (참고용, DB 저장 안 함)
            if (run.cancelled) break;
            try {
                for (Item n : client.search("news", keyword, "date", 1, DISPLAY).items()) addNews(n);
            } catch (CollectException e) {
                if (isStop(e)) {
                    run.stopReason = e.getMessage();
                    break;
                }
                run.notes.add("뉴스 호출 실패(" + keyword + "): " + e.getFailType());
            }
        }
        run.phase = null;
        run.notes.add("검색어 " + run.keywords.size() + "개, 오늘 호출 " + client.usedToday() + "/" + client.dailyLimit()
                + "회, 최근 뉴스 " + news.size() + "건(화면 참고용)");
        if (run.stopReason != null) return "STOPPED";
        if (run.cancelled) return "CANCELLED";
        return "DONE";
    }

    private void handle(Run run, String type, Item item, Set<String> seen) {
        boolean blog = "blog".equals(type);
        String url = blog ? blogUrl(item.link()) : cafeUrl(item.link());
        String site = blog ? "NAVER_BLOG" : "NAVER_CAFE";
        if (url == null) {
            run.skipped.incrementAndGet();
            run.site(site).skipped.incrementAndGet();          // 네이버 블로그·카페 주소가 아님 (크롤링 영역과 겹침)
            return;
        }
        if (!seen.add(url)) return;
        run.candidates.incrementAndGet();
        try {
            LocalDate postedAt = blog ? postdate(item.postdate()) : null;
            String authorKey = blog ? bloggerId(item.bloggerlink(), url) : null;
            ReviewIngestService.Outcome o = ingest.ingestSnippet(url, clean(item.title()), clean(item.description()),
                    postedAt, site, authorKey);
            if (o.saved()) {
                run.saved.incrementAndGet();
                run.site(site).saved.incrementAndGet();
                run.certCounts.computeIfAbsent(o.certCode() + "|" + o.reviewStatus(), x -> new AtomicInteger()).incrementAndGet();
            } else {
                run.skipped.incrementAndGet();
                run.site(site).skipped.incrementAndGet();
                if ("UNREGISTERED".equals(o.result())) {
                    run.certCounts.computeIfAbsent(o.certCode() + "|UNREGISTERED", x -> new AtomicInteger()).incrementAndGet();
                }
            }
        } catch (Exception e) {
            run.failed.incrementAndGet();
            run.site(site).failed.incrementAndGet();
            log.warn("네이버 후기 저장 실패 {}: {}", url, e.getMessage());
        } finally {
            run.processed.incrementAndGet();
        }
    }

    private void addNews(Item n) {
        String link = n.originallink().isBlank() ? n.link() : n.originallink();
        if (link.isBlank()) return;
        news.put(link, new NewsItem(clean(n.title()), link, newsDate(n.pubDate())));
        if (news.size() > NEWS_KEEP * 2) {
            List<NewsItem> all = new ArrayList<>(news.values());
            all.sort((a, b) -> a.date().compareTo(b.date()));
            for (int i = 0; i < all.size() - NEWS_KEEP; i++) news.remove(all.get(i).link());
        }
    }

    // =====================================================================
    // 응답 값 정리 (네트워크 없이 테스트 가능)
    // =====================================================================

    /** <b> 태그·HTML 엔티티 제거 */
    public static String clean(String s) {
        return s == null ? "" : Jsoup.parse(s).text().strip();
    }

    /** 네이버 블로그 글 주소를 https://blog.naver.com/아이디/글번호 한 모양으로. 네이버 블로그가 아니면 null */
    public static String blogUrl(String link) {
        if (link == null) return null;
        Matcher m = BLOG_PATH.matcher(link);
        if (m.find()) return "https://blog.naver.com/" + m.group(1) + "/" + m.group(2);
        if (link.contains("blog.naver.com")) {
            Matcher id = BLOG_ID.matcher(link), no = LOG_NO.matcher(link);
            if (id.find() && no.find()) return "https://blog.naver.com/" + id.group(1) + "/" + no.group(1);
        }
        return null;
    }

    /** 카페 글 주소: https, ? 뒤(검색 추적값) 제거. 네이버 카페가 아니면 null */
    public static String cafeUrl(String link) {
        if (link == null || !link.contains("cafe.naver.com/")) return null;
        String s = link.split("[?#]", 2)[0];
        if (s.startsWith("http://")) s = "https://" + s.substring(7);
        while (s.endsWith("/")) s = s.substring(0, s.length() - 1);
        return s;
    }

    /** postdate(yyyyMMdd) → 날짜 */
    public static LocalDate postdate(String s) {
        if (s == null || !s.matches("\\d{8}")) return null;
        try {
            return LocalDate.parse(s, DateTimeFormatter.BASIC_ISO_DATE);
        } catch (Exception e) {
            return null;
        }
    }

    /** bloggerlink(blog.naver.com/아이디) → 아이디. 없으면 글 주소의 아이디 */
    public static String bloggerId(String bloggerlink, String url) {
        for (String s : new String[]{bloggerlink, url}) {
            if (s == null) continue;
            Matcher m = BLOGGER.matcher(s);
            if (m.find()) return m.group(1);
        }
        return null;
    }

    /** 뉴스 pubDate(RFC 1123) → yyyy-MM-dd (모르면 빈 문자열) */
    public static String newsDate(String pubDate) {
        try {
            return ZonedDateTime.parse(pubDate, DateTimeFormatter.RFC_1123_DATE_TIME.withLocale(Locale.ENGLISH))
                    .toLocalDate().toString();
        } catch (Exception e) {
            return "";
        }
    }

    private static boolean isStop(CollectException e) {
        String t = e.getFailType();
        return "NAVER_DAILY_LIMIT".equals(t) || "NAVER_NO_KEY".equals(t) || "HTTP_401".equals(t) || "HTTP_403".equals(t);
    }

    private static String label(String type) {
        return "blog".equals(type) ? "블로그" : "cafearticle".equals(type) ? "카페" : "뉴스";
    }

    // =====================================================================
    // 실행 1회 상태
    // =====================================================================

    private static final class SiteCount {
        final AtomicInteger saved = new AtomicInteger(), skipped = new AtomicInteger(), failed = new AtomicInteger();
    }

    private static final class Run {
        final List<String> keywords;
        final Instant startedAt = Instant.now();
        final AtomicInteger candidates = new AtomicInteger(), processed = new AtomicInteger(),
                saved = new AtomicInteger(), skipped = new AtomicInteger(), failed = new AtomicInteger();
        final Map<String, SiteCount> bySite = new ConcurrentHashMap<>();
        final Map<String, AtomicInteger> certCounts = new ConcurrentHashMap<>();
        final List<String> notes = new CopyOnWriteArrayList<>();
        volatile String state = "RUNNING";
        volatile String phase;
        volatile boolean cancelled;
        volatile String stopReason;
        volatile Instant finishedAt;

        Run(List<String> keywords) {
            this.keywords = keywords;
        }

        SiteCount site(String name) {
            return bySite.computeIfAbsent(name, x -> new SiteCount());
        }

        void finish(String s) {
            finishedAt = Instant.now();
            state = s;
        }

        CollectJobStatus status() {
            Map<String, String> sites = new LinkedHashMap<>();
            bySite.forEach((s, c) -> sites.put(s, "저장 " + c.saved.get() + "(VALID 0 · 요약문은 PENDING), 건너뜀 "
                    + c.skipped.get() + ", 실패 " + c.failed.get()));
            Instant end = finishedAt == null ? Instant.now() : finishedAt;
            StringBuilder msg = new StringBuilder();
            if (stopReason != null) msg.append("중단: ").append(stopReason).append(" ");
            if (cancelled) msg.append("관리자가 중단했습니다. ");
            msg.append("| ").append(String.join(" / ", notes));
            return new CollectJobStatus(state, "NAVER", 0, candidates.get(), processed.get(), saved.get(), 0,
                    skipped.get(), failed.get(), 0, sites, startedAt.toString(),
                    Duration.between(startedAt, end).toSeconds(), msg.toString().strip(), "NEW", 0,
                    finishedAt == null ? phase : null);
        }

        static CollectJobStatus message(String state, String message) {
            return new CollectJobStatus(state, "NAVER", 0, 0, 0, 0, 0, 0, 0, 0, Map.of(), null, 0, message, "NEW", 0, null);
        }
    }
}
