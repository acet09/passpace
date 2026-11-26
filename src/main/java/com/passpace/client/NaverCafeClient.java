package com.passpace.client;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.passpace.error.exception.CollectException;
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
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [용성·11-23] 네이버 카페 글 본문 가져오기 (회원 전용 글 포함, 가입한 프로젝트 계정의 로그인 쿠키 사용).
 *
 *  - 쿠키: application-local.yml 의 passpace.collect.naver.cafe-cookie ("NID_AUT=…; NID_SES=…"). 비어 있으면 hasCookie()=false
 *    → 쿠키는 저장소·로그에 남기지 않는다 (요청 헤더에만 사용)
 *  - 대상 카페: passpace.collect.naver.cafe-clubs (기본 yjbooks,soojebi,easyadsp = 가입한 카페). 그 밖의 카페 글은 요청하지 않는다
 *  - 카페 글 화면은 자바스크립트로 그려지므로, 화면이 부르는 글 API 의 JSON 에서 본문(contentHtml)·작성일(writeDate)·제목을 읽는다.
 *    공식 문서가 없는 API 라서 경로 두 가지를 차례로 시도한다 (어느 경로가 통했는지 lastRoute 로 남김)
 *      ① apis.naver.com/cafe-web/cafe-articleapi/v2.1/cafes/{카페번호}/articles/{글번호} (카페번호는 CafeGateInfo 로 한 번 찾고 기억)
 *      ② article.cafe.naver.com/gw/v3/cafes/{카페주소}/articles/{글번호} (11-23 시험에서는 500 → 예비용)
 *  - 요청 간격: passpace.collect.review-delay-ms (기본 3초). 429 → 즉시 중단.
 *    401·403 은 글 단위 실패(CAFE_DENIED)로 돌려주고, 연달아 계속 나면 재판정 쪽에서 멈춘다 (쿠키 만료·차단)
 *  - 본문은 메모리에서만 쓰고 저장하지 않는다
 */
@Component
public class NaverCafeClient {

    private static final Logger log = LoggerFactory.getLogger(NaverCafeClient.class);
    private static final Pattern ARTICLE = Pattern.compile("^https?://(?:m\\.)?cafe\\.naver\\.com/([A-Za-z0-9_\\-]+)/(\\d+)");
    private static final ObjectMapper JSON = new ObjectMapper();

    private final String cookie;
    private final List<String> clubs;
    private final String userAgent;
    private final long delayMs;
    private final HttpClient http = HttpClient.newBuilder()
            .version(HttpClient.Version.HTTP_1_1)
            .connectTimeout(Duration.ofSeconds(10))
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();
    private final Map<String, String> cafeIds = new ConcurrentHashMap<>();
    private final Object lock = new Object();
    private long lastRequestAt;
    /** 마지막으로 본문을 받은 경로 (V3 / V2) — 시험 실행 결과 확인용 */
    private volatile String lastRoute;

    /** 카페 글 1건 (본문은 HTML 을 걷어낸 글자) */
    public record CafeArticle(String title, String text, LocalDate postedAt) {
    }

    public NaverCafeClient(@Value("${passpace.collect.naver.cafe-cookie:}") String cookie,
                           @Value("${passpace.collect.naver.cafe-clubs:yjbooks,soojebi,easyadsp}") String clubs,
                           @Value("${passpace.collect.user-agent}") String userAgent,
                           @Value("${passpace.collect.review-delay-ms:3000}") long delayMs) {
        this.cookie = cookie == null ? "" : cookie.strip();
        this.clubs = Arrays.stream(clubs.split(",")).map(String::strip).filter(s -> !s.isEmpty()).toList();
        this.userAgent = userAgent;
        this.delayMs = delayMs;
    }

    public boolean hasCookie() {
        return cookie.contains("NID_AUT") && cookie.contains("NID_SES");
    }

    public List<String> clubs() {
        return clubs;
    }

    public String lastRoute() {
        return lastRoute;
    }

    /** 카페 글 주소 → [카페주소, 글번호]. 카페 글 주소가 아니면 null */
    public static String[] parseUrl(String url) {
        if (url == null) return null;
        Matcher m = ARTICLE.matcher(url);
        return m.find() ? new String[]{m.group(1), m.group(2)} : null;
    }

    /** 글 1건. 권한이 없거나(등업 필요·삭제) 본문이 없으면 CollectException("CAFE_DENIED") */
    public CafeArticle fetch(String url) {
        if (!hasCookie()) {
            throw new CollectException("CAFE_NO_COOKIE", "카페 로그인 쿠키가 없습니다 (application-local.yml 의 passpace.collect.naver.cafe-cookie).");
        }
        String[] p = parseUrl(url);
        if (p == null) throw new CollectException("CAFE_BAD_URL", "카페 글 주소가 아닙니다: " + url);
        String club = p[0], articleId = p[1];
        String referer = "https://cafe.naver.com/" + club + "/" + articleId;

        // [11-23 시험] ② v2 경로로 본문을 받았고 ① v3 경로는 500 → v2 를 먼저, 안 되면 v3
        String cafeId = cafeId(club, referer);
        Res v2 = null;
        if (cafeId != null) {
            v2 = get("https://apis.naver.com/cafe-web/cafe-articleapi/v2.1/cafes/" + cafeId + "/articles/" + articleId
                    + "?useCafeId=true", referer);
            Optional<CafeArticle> a = v2.status() == 200 ? parseArticle(v2.body()) : Optional.empty();
            if (a.isPresent()) {
                lastRoute = "V2";
                return a.get();
            }
            // 권한 없음(등업 필요 등)은 v3 로 다시 물어도 같으므로 바로 돌려준다
            if (v2.status() == 401 || v2.status() == 403) {
                throw new CollectException("CAFE_DENIED", "본문을 받지 못함 (v2 " + v2.status() + "): " + errorHint(v2.body()));
            }
        }
        Res v3 = get("https://article.cafe.naver.com/gw/v3/cafes/" + club + "/articles/" + articleId
                + "?useCafeId=false", referer);
        Optional<CafeArticle> a = v3.status() == 200 ? parseArticle(v3.body()) : Optional.empty();
        if (a.isPresent()) {
            lastRoute = "V3";
            return a.get();
        }
        throw new CollectException("CAFE_DENIED", "본문을 받지 못함 (v2 " + (v2 == null ? "카페번호 없음" : v2.status())
                + ", v3 " + v3.status() + "): " + errorHint(v2 != null && !v2.body().isBlank() ? v2.body() : v3.body()));
    }

    private String cafeId(String club, String referer) {
        String id = cafeIds.get(club);
        if (id != null) return id;
        Res r = get("https://apis.naver.com/cafe-web/cafe2/CafeGateInfo.json?cluburl=" + club, referer);
        if (r.status() != 200) return null;
        try {
            JsonNode n = findField(JSON.readTree(r.body()), "cafeId");
            if (n != null && !n.asText().isBlank()) {
                cafeIds.put(club, n.asText());
                return n.asText();
            }
        } catch (IOException e) {
            log.info("카페번호 응답 해석 실패 {}: {}", club, e.getMessage());
        }
        return null;
    }

    // =====================================================================
    // 응답 해석 (네트워크 없이 테스트 가능)
    // =====================================================================

    /** 글 API 응답 JSON 에서 제목·본문·작성일을 찾는다. 경로마다 감싸는 구조가 달라 필드 이름으로 찾는다. 본문이 없으면 empty */
    public static Optional<CafeArticle> parseArticle(String json) {
        try {
            JsonNode root = JSON.readTree(json);
            JsonNode article = findObjectWith(root, "contentHtml");
            if (article == null) return Optional.empty();
            String html = article.path("contentHtml").asText("");
            String text = Jsoup.parse(html).text().strip();
            if (text.isEmpty()) return Optional.empty();
            String title = article.path("subject").asText(null);
            return Optional.of(new CafeArticle(title, text, toDate(article.get("writeDate"))));
        } catch (IOException | RuntimeException e) {
            return Optional.empty();
        }
    }

    /** writeDate: 밀리초 숫자 또는 날짜 글자 */
    static LocalDate toDate(JsonNode n) {
        if (n == null || n.isNull()) return null;
        if (n.isNumber() || n.asText().matches("\\d{12,}")) {
            return Instant.ofEpochMilli(n.asLong()).atZone(ZoneId.of("Asia/Seoul")).toLocalDate();
        }
        String s = n.asText();
        return s.length() >= 10 && s.substring(0, 10).matches("\\d{4}[.\\-]\\d{2}[.\\-]\\d{2}")
                ? LocalDate.parse(s.substring(0, 10).replace('.', '-')) : null;
    }

    /** 오류 응답에서 원인 문구만 짧게 (로그·실행 결과 표시용, 본문 아님) */
    static String errorHint(String body) {
        if (body == null || body.isBlank()) return "빈 응답";
        try {
            JsonNode root = JSON.readTree(body);
            List<String> parts = new ArrayList<>();
            for (String f : List.of("errorCode", "code", "reason", "message", "msg")) {
                JsonNode n = findField(root, f);
                if (n != null && n.isValueNode() && !n.asText().isBlank()) parts.add(f + "=" + n.asText());
            }
            if (!parts.isEmpty()) return String.join(", ", parts);
        } catch (IOException ignored) {
            // JSON 이 아니면 앞부분만
        }
        String s = body.replaceAll("\\s+", " ");
        return s.length() > 120 ? s.substring(0, 120) : s;
    }

    static JsonNode findField(JsonNode node, String name) {
        if (node == null) return null;
        if (node.has(name)) return node.get(name);
        for (JsonNode child : node) {
            JsonNode f = findField(child, name);
            if (f != null) return f;
        }
        return null;
    }

    static JsonNode findObjectWith(JsonNode node, String name) {
        if (node == null) return null;
        if (node.isObject() && node.has(name)) return node;
        for (JsonNode child : node) {
            JsonNode f = findObjectWith(child, name);
            if (f != null) return f;
        }
        return null;
    }

    // =====================================================================
    // 요청 (요청 간격 지킴, 429 는 즉시 중단)
    // =====================================================================

    private record Res(int status, String body) {
    }

    private Res get(String url, String referer) {
        HttpRequest req = HttpRequest.newBuilder(URI.create(url))
                .timeout(Duration.ofSeconds(20))
                .header("User-Agent", userAgent)
                .header("Accept", "application/json, text/plain, */*")
                .header("Accept-Language", "ko-KR,ko;q=0.9")
                .header("Referer", referer)
                .header("Cookie", cookie)
                .GET().build();
        HttpResponse<String> res;
        synchronized (lock) {
            long wait = lastRequestAt + delayMs - System.currentTimeMillis();
            if (wait > 0) sleep(wait);
            lastRequestAt = System.currentTimeMillis();
            try {
                res = http.send(req, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            } catch (IOException e) {
                throw new CollectException("NETWORK", "연결 실패(" + URI.create(url).getHost() + "): " + e.getMessage());
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new CollectException("NETWORK", "요청이 중단되었습니다");
            }
        }
        int s = res.statusCode();
        if (s == 429) {
            throw new CollectException("HTTP_429", "네이버 카페가 요청 과다로 제한했습니다(429) → 중단: " + errorHint(res.body()));
        }
        // 401·403 은 "그 글을 볼 권한 없음(등업 필요·비공개)"일 수도 있어 여기서 멈추지 않는다.
        // 연달아 계속 나면(쿠키 만료·차단) ReviewRejudgeService 가 멈춘다
        return new Res(s, res.body() == null ? "" : res.body());
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
