package com.passpace.client;

import com.passpace.crawler.ListingParser.ListingLink;
import org.openqa.selenium.By;
import org.openqa.selenium.JavascriptExecutor;
import org.openqa.selenium.WebDriver;
import org.openqa.selenium.chrome.ChromeDriver;
import org.openqa.selenium.chrome.ChromeOptions;
import org.openqa.selenium.support.ui.ExpectedConditions;
import org.openqa.selenium.support.ui.WebDriverWait;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.function.BooleanSupplier;
import java.util.function.Consumer;

/**
 * [용성] 티스토리 통합 검색 화면 읽기 (글 주소·제목·작성일만).
 *
 * 왜 브라우저인가: 티스토리 검색 결과는 브라우저에서 스크립트가 실행된 뒤에 그려져서,
 * 글자만 받는 HTTP 요청으로는 결과가 비어 있다. 내부 API 를 직접 부르는 것은 서비스 모방·우회에 해당할 수 있어 쓰지 않고,
 * 사람이 보는 것과 같은 방식(PC 에 설치된 크롬을 화면 없이 실행)으로 공개 검색 화면만 읽는다.
 *
 * 정책 (기획안 7.1 · 카카오 통합약관 제12조 검토)
 *  - www.tistory.com/robots.txt 없음(404) → 제한 없음. 수집 전에 매번 다시 확인한다 (ReviewPageFetcher)
 *  - 검색 화면 사이 간격 tistory-search-delay-ms(기본 5초), 검색어당 최대 tistory-search-pages 쪽
 *  - 결과가 비거나 화면이 안 뜨면(차단 가능성) 그 검색은 즉시 멈춤. 차단을 피하는 기능은 넣지 않는다
 *  - 브라우저 이름(User-Agent)에 우리 봇 이름을 붙여 누가 접속하는지 밝힌다
 *  - 본문은 여기서 읽지 않는다. 찾은 글은 기존 수집기가 각 블로그의 robots.txt 를 지키며 가져온다
 *  - 크롬이 없거나 실행에 실패하면 이 기능만 꺼지고 나머지 수집은 그대로 동작한다
 */
@Component
public class TistorySearchBrowser {

    private static final Logger log = LoggerFactory.getLogger(TistorySearchBrowser.class);
    static final String SEARCH = "https://www.tistory.com/search?type=post&sort=ACCURACY&keyword=";
    /** 검색 결과 1건: [주소, 제목(첫 줄), 마지막 줄(작성일 yyyy.MM.dd)] */
    private static final String EXTRACT_JS = """
            return Array.from(document.querySelectorAll('a.link_cont')).map(function (a) {
              var t = (a.innerText || '').trim().split('\\n');
              return [a.href, t[0] || '', t[t.length - 1] || ''];
            });""";

    private final boolean enabled;
    private final int maxPages;
    private final long delayMs;
    private final String userAgent;
    private final ReviewPageFetcher fetcher;
    private volatile String unavailableReason;

    public TistorySearchBrowser(@Value("${passpace.collect.tistory-search-enabled:true}") boolean enabled,
                                @Value("${passpace.collect.tistory-search-pages:5}") int maxPages,
                                @Value("${passpace.collect.tistory-search-delay-ms:5000}") long delayMs,
                                @Value("${passpace.collect.user-agent}") String botName,
                                ReviewPageFetcher fetcher) {
        this.enabled = enabled;
        this.maxPages = Math.max(1, Math.min(10, maxPages));
        this.delayMs = Math.max(3000, delayMs);
        this.userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome Safari/537.36 "
                + botName;
        this.fetcher = fetcher;
    }

    /** 사용할 수 없는 이유 (사용 가능하면 null) */
    public String unavailableReason() {
        return enabled ? unavailableReason : "설정에서 꺼져 있음 (passpace.collect.tistory-search-enabled)";
    }

    /** 검색 결과 1건 (본문 없음) */
    public record Hit(String url, String title, LocalDate postedAt) {
    }

    /**
     * 검색어 여러 개를 차례로 검색한다. 크롬은 이 메서드 안에서 한 번 켜고 끝나면 닫는다 (스레드 1개에서만 사용).
     * @param onHits    검색어 1쪽을 읽을 때마다 결과를 넘겨받음 (찾는 대로 수집 대기열에 넣기 위해)
     * @param onPhase   진행 표시 ("티스토리 검색 2/10 (3쪽)")
     * @param stop      true 가 되면 즉시 멈춤
     * @return 읽은 쪽 수
     */
    public int searchAll(List<String> keywords, Consumer<List<ListingLink>> onHits, Consumer<String> onPhase,
                         BooleanSupplier stop) {
        if (!enabled || keywords.isEmpty()) return 0;
        if (!fetcher.allowedByRobots(SEARCH + "x")) {
            unavailableReason = "www.tistory.com robots.txt 가 검색 화면을 금지함";
            log.warn(unavailableReason);
            return 0;
        }
        WebDriver driver;
        try {
            driver = startChrome();
        } catch (Exception e) {
            unavailableReason = "크롬을 실행하지 못했습니다 (PC 에 크롬 설치 필요): " + e.getMessage();
            log.warn(unavailableReason);
            return 0;
        }
        unavailableReason = null;
        int pagesRead = 0;
        try {
            int k = 0;
            for (String keyword : keywords) {
                k++;
                for (int page = 1; page <= maxPages; page++) {
                    if (stop.getAsBoolean()) return pagesRead;
                    onPhase.accept("티스토리 검색 " + k + "/" + keywords.size() + " '" + keyword + "' " + page + "쪽");
                    List<Hit> hits = readPage(driver, keyword, page);
                    pagesRead++;
                    if (hits.isEmpty()) break;              // 결과 끝 (또는 화면이 안 뜸 → 그 검색어는 멈춤)
                    List<ListingLink> links = new ArrayList<>();
                    for (Hit h : hits) links.add(new ListingLink(h.url(), h.title(), h.postedAt()));
                    onHits.accept(links);
                    sleep(delayMs);
                }
            }
        } finally {
            try {
                driver.quit();
            } catch (Exception ignored) {
                // 이미 닫힘
            }
        }
        return pagesRead;
    }

    /** 검색어 1개 1쪽만 (관리자 화면 "찾은 글 보기") */
    public List<Hit> searchOnce(String keyword) {
        if (!enabled) return List.of();
        if (!fetcher.allowedByRobots(SEARCH + "x")) return List.of();
        WebDriver driver = startChrome();
        try {
            return readPage(driver, keyword, 1);
        } finally {
            driver.quit();
        }
    }

    private WebDriver startChrome() {
        ChromeOptions o = new ChromeOptions();
        o.addArguments("--headless=new", "--disable-gpu", "--no-first-run", "--disable-extensions",
                "--lang=ko-KR", "--window-size=1280,2000", "--user-agent=" + userAgent);
        WebDriver d = new ChromeDriver(o);
        d.manage().timeouts().pageLoadTimeout(Duration.ofSeconds(30));
        return d;
    }

    @SuppressWarnings("unchecked")
    private List<Hit> readPage(WebDriver driver, String keyword, int page) {
        String url = SEARCH + URLEncoder.encode(keyword, StandardCharsets.UTF_8) + "&page=" + page;
        try {
            driver.get(url);
            new WebDriverWait(driver, Duration.ofSeconds(15))
                    .until(ExpectedConditions.presenceOfElementLocated(By.cssSelector("a.link_cont, .box_empty, .wrap_empty")));
            Object raw = ((JavascriptExecutor) driver).executeScript(EXTRACT_JS);
            List<Hit> out = new ArrayList<>();
            if (raw instanceof List<?> rows) {
                for (Object row : rows) {
                    if (!(row instanceof List<?> r) || r.size() < 3) continue;
                    String href = String.valueOf(r.get(0));
                    if (!href.contains(".tistory.com/")) continue;
                    out.add(new Hit(href, String.valueOf(r.get(1)), parseDate(String.valueOf(r.get(2)))));
                }
            }
            return out;
        } catch (Exception e) {
            log.info("티스토리 검색 화면을 읽지 못함 ({} {}쪽): {}", keyword, page, e.getMessage());
            return List.of();
        }
    }

    /** "2026.10.26" → 날짜 (형식이 다르면 null) */
    static LocalDate parseDate(String s) {
        if (s == null) return null;
        String t = s.strip();
        if (!t.matches("\\d{4}\\.\\d{2}\\.\\d{2}")) return null;
        try {
            return LocalDate.of(Integer.parseInt(t.substring(0, 4)), Integer.parseInt(t.substring(5, 7)),
                    Integer.parseInt(t.substring(8, 10)));
        } catch (RuntimeException e) {
            return null;
        }
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
