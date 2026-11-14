package com.passpace.client;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.passpace.error.exception.CollectException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * [용성·11-14] 네이버 검색 API 클라이언트 (blog · cafearticle · news)
 *  GET https://openapi.naver.com/v1/search/{type}.json?query=&display=&start=&sort=
 *  헤더 X-Naver-Client-Id / X-Naver-Client-Secret
 *
 * 네이버와 사전 협의(하루 호출 한도 25,000회 안에서 자유 사용)에 따라
 *  - 하루 사용량 카운터: 설정값(기본 20,000)을 넘으면 중단. 날짜가 바뀌면 0. 서버 재시작 시 초기화되는 메모리 카운터
 *  - 호출 간격 기본 100ms
 *  - 429 중 하루 한도 초과(errorCode 010)는 재시도 없이 즉시 중단, 그 밖의 429·5xx 는 대기 후 2번 다시 시도
 *  - 401·403 은 즉시 중단 (키 오류)
 * 키는 application-local.yml 의 passpace.collect.naver.client-id / client-secret (비어 있으면 hasKey()=false)
 */
@Component
public class NaverSearchClient {

    private static final Logger log = LoggerFactory.getLogger(NaverSearchClient.class);
    private static final String BASE = "https://openapi.naver.com/v1/search/";
    private static final int RETRIES = 2;
    private static final long RETRY_WAIT_MS = 3_000;

    /** 검색 결과 1건 (종류에 없는 필드는 빈 문자열) */
    public record Item(String title, String link, String description, String postdate, String bloggerlink,
                       String originallink, String pubDate) {
    }

    public record Page(int total, List<Item> items) {
    }

    private final ObjectMapper objectMapper;
    private final String clientId;
    private final String clientSecret;
    private final long callDelayMs;
    private final int dailyLimit;
    private final HttpClient http = HttpClient.newBuilder()
            .version(HttpClient.Version.HTTP_1_1)
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    private LocalDate counterDate = LocalDate.now();
    private int usedToday;
    private long lastCallAt;

    public NaverSearchClient(ObjectMapper objectMapper,
                             @Value("${passpace.collect.naver.client-id:}") String clientId,
                             @Value("${passpace.collect.naver.client-secret:}") String clientSecret,
                             @Value("${passpace.collect.naver.call-delay-ms:100}") long callDelayMs,
                             @Value("${passpace.collect.naver.daily-limit:20000}") int dailyLimit) {
        this.objectMapper = objectMapper;
        this.clientId = clientId == null ? "" : clientId.trim();
        this.clientSecret = clientSecret == null ? "" : clientSecret.trim();
        this.callDelayMs = Math.max(0, callDelayMs);
        this.dailyLimit = Math.min(25_000, Math.max(1, dailyLimit));
    }

    public boolean hasKey() {
        return !clientId.isEmpty() && !clientSecret.isEmpty();
    }

    public synchronized int usedToday() {
        rollDate();
        return usedToday;
    }

    public int dailyLimit() {
        return dailyLimit;
    }

    /**
     * @param type    blog / cafearticle / news
     * @param sort    sim(정확도) / date(최신)
     * @param start   1~1000
     * @param display 1~100
     */
    public Page search(String type, String query, String sort, int start, int display) {
        if (!hasKey()) throw new CollectException("NAVER_NO_KEY", "네이버 검색 API 키가 없습니다 (application-local.yml 의 passpace.collect.naver.client-id·client-secret).");
        String url = BASE + type + ".json?query=" + URLEncoder.encode(query, StandardCharsets.UTF_8)
                + "&display=" + Math.max(1, Math.min(100, display))
                + "&start=" + Math.max(1, Math.min(1000, start))
                + "&sort=" + ("date".equals(sort) ? "date" : "sim");
        for (int attempt = 0; ; attempt++) {
            HttpResponse<String> res = send(url);
            int code = res.statusCode();
            if (code == 200) return parse(res.body());
            if (code == 401 || code == 403) {
                throw new CollectException("HTTP_" + code, "네이버 검색 API 인증 실패(" + code + "). 키·사용 API 설정을 확인하세요.");
            }
            if (code == 429 && "010".equals(errorCode(res.body()))) {
                throw new CollectException("NAVER_DAILY_LIMIT", "네이버 검색 API 하루 호출 한도를 넘었습니다(errorCode 010). 내일 다시 실행하세요.");
            }
            if ((code == 429 || code >= 500) && attempt < RETRIES) {
                log.info("네이버 검색 API {} → {}초 뒤 다시 시도 ({})", code, RETRY_WAIT_MS * (attempt + 1) / 1000, errorCode(res.body()));
                sleep(RETRY_WAIT_MS * (attempt + 1));
                continue;
            }
            throw new CollectException("HTTP_" + code, "네이버 검색 API 호출 실패(" + code + ", errorCode " + errorCode(res.body()) + ")");
        }
    }

    /** 하루 사용량을 확인·증가하고 호출 간격을 지켜 요청 1번 */
    private HttpResponse<String> send(String url) {
        synchronized (this) {
            rollDate();
            if (usedToday >= dailyLimit) {
                throw new CollectException("NAVER_DAILY_LIMIT", "오늘 사용량이 설정 한도(" + dailyLimit + "회)에 도달해 중단합니다.");
            }
            long wait = lastCallAt + callDelayMs - System.currentTimeMillis();
            if (wait > 0) sleep(wait);
            lastCallAt = System.currentTimeMillis();
            usedToday++;
        }
        HttpRequest req = HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofSeconds(20))
                .header("X-Naver-Client-Id", clientId)
                .header("X-Naver-Client-Secret", clientSecret)
                .header("Accept", "application/json")
                .GET().build();
        try {
            return http.send(req, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        } catch (IOException e) {
            throw new CollectException("NETWORK", "네이버 검색 API 연결 실패: " + e.getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new CollectException("NETWORK", "요청이 중단되었습니다");
        }
    }

    Page parse(String body) {
        JsonNode root = readJson(body);
        List<Item> items = new ArrayList<>();
        for (JsonNode n : root.path("items")) {
            items.add(new Item(n.path("title").asText(""), n.path("link").asText(""), n.path("description").asText(""),
                    n.path("postdate").asText(""), n.path("bloggerlink").asText(""),
                    n.path("originallink").asText(""), n.path("pubDate").asText("")));
        }
        return new Page(root.path("total").asInt(0), items);
    }

    private String errorCode(String body) {
        try {
            return objectMapper.readTree(body).path("errorCode").asText("");
        } catch (Exception e) {
            return "";
        }
    }

    private JsonNode readJson(String body) {
        try {
            return objectMapper.readTree(body);
        } catch (IOException e) {
            throw new CollectException("PARSE_ERROR", "네이버 응답을 JSON 으로 읽지 못했습니다: " + e.getMessage());
        }
    }

    private void rollDate() {
        LocalDate today = LocalDate.now();
        if (!today.equals(counterDate)) {
            counterDate = today;
            usedToday = 0;
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
