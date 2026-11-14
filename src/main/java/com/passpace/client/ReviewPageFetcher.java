package com.passpace.client;

import com.passpace.error.exception.CollectException;

import com.passpace.crawler.AuthorHasher;
import com.passpace.crawler.PostPageParser;
import com.passpace.crawler.PostPageParser.PostPage;
import com.passpace.crawler.ReviewSite;
import com.passpace.crawler.UrlText;
import com.passpace.dto.collect.CollectDtos.FetchedPage;
import org.jsoup.Jsoup;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.LocalDate;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import com.passpace.crawler.DcinsideParser;
import org.jsoup.nodes.Document;

/**
 * [용성] 후기 페이지 가져오기.
 * 수집 정책(기획안 7.1.2 + 수집정보 목록)
 *  - robots.txt 금지 경로는 목록·글 모두 가져오지 않는다 (RobotsRules)
 *  - 요청 사이 간격: 사이트(velog / 티스토리 전체)별로 따로 지킨다.
 *      velog 1.5초(review-delay-ms), 티스토리 0.5초(tistory-delay-ms).
 *      robots.txt 에 Crawl-delay 가 있으면 둘 중 큰 값을 쓴다.
 *  - 403·429 응답이면 즉시 전체 중단 (CollectException)
 *  - 본문은 maxChars 까지만 메모리에 두고 저장하지 않는다
 *  - 로그인 화면으로 넘어가는 글은 수집하지 않는다 (공개 글만)
 *  - 작성자 아이디는 여기서 해시로 바꾸고 원본은 밖으로 내보내지 않는다
 *
 * [4차 수정] velog·티스토리를 동시에 수집할 수 있도록 스레드 안전하게 바꿨다.
 *  - 같은 사이트 요청끼리는 잠금으로 순서대로 보내고 간격을 지킨다 (사이트 안에서는 동시 요청 없음)
 *  - robots.txt 는 서버가 켜져 있는 동안 24시간 재사용한다 (실행마다 다시 받지 않음)
 */
@Component
public class ReviewPageFetcher {

    private static final Logger log = LoggerFactory.getLogger(ReviewPageFetcher.class);

    /** 서버 오류(5xx)·응답 없음일 때 최대 시도 횟수와 대기 간격 (velog 는 가끔 504 를 낸다) */
    private static final int MAX_ATTEMPTS = 3;
    private static final long RETRY_WAIT_MS = 5_000;
    /** robots.txt 재사용 시간 */
    private static final long ROBOTS_TTL_MS = Duration.ofHours(24).toMillis();
    /** Crawl-delay 상한 (비정상적으로 큰 값이면 그 사이트 수집이 사실상 멈추므로 60초로 자른다) */
    private static final long MAX_CRAWL_DELAY_MS = 60_000;

    private final String userAgent;
    private final int maxChars;
    private final Map<String, Timing> timings;
    /** scheme://host[:port] → robots 규칙 */
    private final Map<String, RobotsEntry> robotsCache = new ConcurrentHashMap<>();
    /**
     * 사이트별 "잠시 쉬기" 종료 시각. 429(요청 과다)·403 을 받으면 그 사이트에는 이 시각까지 요청하지 않는다.
     * Retry-After 헤더가 있으면 그 값, 없으면 30분.
     */
    private final Map<String, Long> cooldownUntil = new ConcurrentHashMap<>();
    private static final long DEFAULT_COOLDOWN_MS = Duration.ofMinutes(30).toMillis();

    /** 사이트별 마지막 요청 시각 (잠금 객체 겸용) */
    private final Map<String, long[]> lastRequestAt = new ConcurrentHashMap<>();

    private final HttpClient http = HttpClient.newBuilder()
            .version(HttpClient.Version.HTTP_1_1)
            .connectTimeout(Duration.ofSeconds(10))
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();

    /** 사이트별 요청 간격·응답 대기 */
    record Timing(long delayMs, Duration timeout) {
    }

    private record RobotsEntry(RobotsRules rules, long loadedAt) {
    }

    public ReviewPageFetcher(@Value("${passpace.collect.user-agent}") String userAgent,
                             @Value("${passpace.collect.review-delay-ms:1500}") long delayMs,
                             @Value("${passpace.collect.review-timeout-seconds:45}") long timeoutSeconds,
                             @Value("${passpace.collect.tistory-delay-ms:500}") long tistoryDelayMs,
                             @Value("${passpace.collect.tistory-timeout-seconds:20}") long tistoryTimeoutSeconds,
                             @Value("${passpace.collect.review-max-chars}") int maxChars) {
        this.userAgent = userAgent;
        this.maxChars = maxChars;
        Timing base = new Timing(delayMs, Duration.ofSeconds(timeoutSeconds));
        this.timings = Map.of(
                ReviewSite.VELOG.name(), base,
                ReviewSite.TISTORY.name(), new Timing(tistoryDelayMs, Duration.ofSeconds(tistoryTimeoutSeconds)),
                ReviewSite.DCINSIDE.name(), new Timing(DCINSIDE_DELAY_MS, Duration.ofSeconds(timeoutSeconds)),
                OTHER, base);
    }

    private static final String OTHER = "OTHER";
    /** [11-14] 신규 사이트(디시) 요청 간격 기본 2초 */
    private static final long DCINSIDE_DELAY_MS = 2_000;

    /**
     * [11-14] 크롤링 정책 폐기(2026-11-14)로 robots.txt 금지 검사는 설정으로 끌 수 있게 했다 (기본 꺼짐).
     * 403·429 즉시 중단, 사이트별 요청 간격, 재시도는 그대로 지킨다.
     */
    @Value("${passpace.collect.robots-check:false}")
    private boolean robotsCheck;

    /** 개별 글 페이지 → 본문·작성일·작성자 해시. 본문은 메모리에서만 쓴다 */
    public FetchedPage fetchPost(String url, ReviewSite site, AuthorHasher hasher) {
        String ascii = UrlText.toAscii(url);
        Page res = get(ascii, MAX_ATTEMPTS);
        String finalUrl = res.finalUrl();
        if (finalUrl.contains("/login") || finalUrl.contains("accounts.kakao") || finalUrl.contains("/auth/")) {
            throw new CollectException("LOGIN_REQUIRED", "로그인해야 보이는 글이라 수집하지 않습니다: " + url);
        }
        if (site == ReviewSite.DCINSIDE) {
            // [11-14] 디시: 작성자가 주소에 없어 글 페이지에서 뽑는다 (고정닉 아이디 / 유동닉 닉네임+IP 앞 두 자리)
            Document doc = Jsoup.parse(res.body(), finalUrl);
            PostPage dc = DcinsideParser.post(doc, maxChars);
            return new FetchedPage(ascii, dc.title(), dc.text(), dc.postedAt(),
                    hasher.hash(site, DcinsideParser.authorKey(doc)), dc.noReprint());
        }
        PostPage page = PostPageParser.parse(Jsoup.parse(res.body(), finalUrl), site, LocalDate.now(), maxChars);
        return new FetchedPage(ascii, page.title(), page.text(), page.postedAt(),
                hasher.hash(site, site.authorKey(ascii)), page.noReprint());
    }

    /** 목록·피드 페이지 원문 (링크 추출용, 저장하지 않음) */
    public String fetchListing(String url) {
        return get(UrlText.toAscii(url), MAX_ATTEMPTS).body();
    }

    /**
     * 목록 페이지를 빠르게: 5xx·응답 없음이면 1번만 다시 시도한다.
     * 목록은 다음 수집 때 다시 읽으면 되므로, 글 본문(3번 시도)보다 오래 붙잡지 않는다.
     */
    public String fetchListingQuick(String url) {
        return get(UrlText.toAscii(url), 2).body();
    }

    /** 받은 페이지: 리다이렉트 후 최종 주소, 상태 코드, 본문 */
    record Page(String finalUrl, int status, String body, String retryAfter) {
    }

    /** 그 사이트가 쉬는 중이면 남은 초 (아니면 0) */
    public long cooldownSeconds(String siteKey) {
        long left = cooldownUntil.getOrDefault(siteKey, 0L) - System.currentTimeMillis();
        return left > 0 ? (left + 999) / 1000 : 0;
    }

    private Page get(String asciiUrl, int attempts) {
        URI uri = URI.create(asciiUrl);
        String siteKey = siteKey(uri);
        long wait = cooldownSeconds(siteKey);
        if (wait > 0) {
            throw new CollectException("COOLDOWN", siteKey + " 이(가) 요청을 제한해 쉬는 중입니다 (약 " + (wait / 60 + 1) + "분 남음): " + asciiUrl);
        }
        if (robotsCheck && !isAllowedByRobots(uri)) {
            throw new CollectException("ROBOTS_DENIED", "robots.txt 에서 금지한 경로입니다: " + asciiUrl);
        }
        Page page = send(uri, attempts);
        if (page.status() == 403 || page.status() == 429) {
            long ms = retryAfterMs(page.retryAfter());
            cooldownUntil.put(siteKey, System.currentTimeMillis() + ms);
            throw new CollectException("HTTP_" + page.status(), siteKey + " 이(가) 접근을 제한했습니다(" + page.status()
                    + ") → 이 사이트는 약 " + (ms / 60_000) + "분 쉽니다: " + asciiUrl);
        }
        if (page.status() >= 400) {
            throw new CollectException("HTTP_" + page.status(), "페이지를 가져오지 못했습니다: " + asciiUrl);
        }
        return page;
    }

    /**
     * 실제 요청 (요청 간격 지킴).
     * jsoup 기본 연결은 PC 에서 HTTP/2 협상 중 응답 없이 멈추는 경우가 있어
     * 자바 HttpClient 를 HTTP/1.1 로 고정해 직접 요청하고, 받은 문자열만 jsoup 으로 해석한다.
     * 서버가 느려 5xx 를 주거나 응답이 없으면 5초·10초 쉬고 최대 3번까지 시도한다.
     */
    private Page send(URI uri, int attempts) {
        CollectException last = null;
        for (int attempt = 1; attempt <= attempts; attempt++) {
            if (attempt > 1) {
                sleep(RETRY_WAIT_MS * (attempt - 1));     // 5초, 10초 쉬고 다시 (서버 부담을 늘리지 않게)
            }
            try {
                Page page = sendOnce(uri);
                if (page.status() < 500 || attempt == attempts) {
                    return page;
                }
                log.info("{} 서버 응답 {} → {}회째 다시 시도", uri.getHost(), page.status(), attempt + 1);
            } catch (CollectException e) {
                last = e;
                log.info("{} 응답 없음 → {}회째 다시 시도 ({})", uri.getHost(), attempt + 1, e.getMessage());
            }
        }
        throw last;
    }

    private Page sendOnce(URI uri) {
        String siteKey = siteKey(uri);
        Timing timing = timings.getOrDefault(siteKey, timings.get(OTHER));
        HttpRequest req = HttpRequest.newBuilder(uri)
                .timeout(timing.timeout())
                .header("User-Agent", userAgent)
                .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
                .header("Accept-Language", "ko-KR,ko;q=0.9")
                .GET().build();
        // 같은 사이트 요청은 잠금 안에서 하나씩 보낸다 → 사이트 안에서는 동시 요청이 생기지 않는다
        long[] last = lastRequestAt.computeIfAbsent(siteKey, k -> new long[]{0});
        synchronized (last) {
            long wait = last[0] + effectiveDelay(uri, timing) - System.currentTimeMillis();
            if (wait > 0) sleep(wait);
            last[0] = System.currentTimeMillis();
            try {
                HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
                return new Page(res.uri().toString(), res.statusCode(), res.body(),
                        res.headers().firstValue("Retry-After").orElse(null));
            } catch (IOException e) {
                throw new CollectException("NETWORK", "연결 실패(" + uri.getHost() + "): " + e.getMessage());
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new CollectException("NETWORK", "요청이 중단되었습니다");
            }
        }
    }

    /** Retry-After: 초 단위 숫자만 해석 (날짜 형식이거나 없으면 30분). 최소 1분, 최대 6시간 */
    static long retryAfterMs(String value) {
        if (value != null) {
            try {
                long sec = Long.parseLong(value.strip());
                return Math.max(60_000, Math.min(sec * 1000, Duration.ofHours(6).toMillis()));
            } catch (NumberFormatException ignored) {
                // 날짜 형식 등 → 기본값
            }
        }
        return DEFAULT_COOLDOWN_MS;
    }

    /** 사이트 간격과 그 호스트 robots.txt 의 Crawl-delay 중 큰 값 */
    private long effectiveDelay(URI uri, Timing timing) {
        RobotsEntry e = robotsCache.get(hostKey(uri));
        long crawlDelay = e == null ? 0 : Math.min(e.rules().crawlDelayMs(), MAX_CRAWL_DELAY_MS);
        return Math.max(timing.delayMs(), crawlDelay);
    }

    /** velog / 티스토리(모든 블로그를 하나로) / 그 밖 */
    static String siteKey(URI uri) {
        Optional<ReviewSite> site = ReviewSite.of(uri.toString());
        return site.map(Enum::name).orElse(OTHER);
    }

    private static String hostKey(URI uri) {
        return uri.getScheme() + "://" + uri.getHost() + (uri.getPort() == -1 ? "" : ":" + uri.getPort());
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    /** 외부(티스토리 검색 브라우저 등)에서 쓰는 robots.txt 확인 */
    public boolean allowedByRobots(String url) {
        if (!robotsCheck) return true;
        try {
            return isAllowedByRobots(URI.create(UrlText.toAscii(url)));
        } catch (RuntimeException e) {
            return false;
        }
    }

    /** robots.txt 확인 (호스트별로 한 번 읽고 24시간 재사용) */
    boolean isAllowedByRobots(URI uri) {
        String host = hostKey(uri);
        RobotsEntry entry = robotsCache.get(host);
        if (entry == null || System.currentTimeMillis() - entry.loadedAt() > ROBOTS_TTL_MS) {
            entry = new RobotsEntry(loadRobots(host), System.currentTimeMillis());
            robotsCache.put(host, entry);
        }
        String path = uri.getRawPath() == null || uri.getRawPath().isEmpty() ? "/" : uri.getRawPath();
        if (uri.getRawQuery() != null) path += "?" + uri.getRawQuery();
        return entry.rules().isAllowed(path);
    }

    /** 관리자가 robots.txt 를 강제로 다시 읽게 할 때만 사용 (수집 실행마다 지우지 않는다) */
    public void clearRobotsCache() {
        robotsCache.clear();
    }

    private RobotsRules loadRobots(String host) {
        Page page;
        try {
            page = send(URI.create(host + "/robots.txt"), MAX_ATTEMPTS);
        } catch (CollectException e) {
            // robots.txt 를 확인할 수 없으면 안전하게 전체 금지
            log.warn("{} robots.txt 확인 실패 → 수집하지 않음: {}", host, e.getMessage());
            return RobotsRules.disallowAll();
        }
        if (page.status() >= 200 && page.status() < 300) {
            return RobotsRules.parse(page.body(), userAgent.split("/")[0]);
        }
        if (page.status() >= 400 && page.status() < 500) {
            log.info("{} robots.txt 없음({}) → 제한 없음으로 판단", host, page.status());
            return RobotsRules.allowAll();
        }
        log.warn("{} robots.txt 서버 오류({}) → 수집하지 않음", host, page.status());
        return RobotsRules.disallowAll();
    }
}
