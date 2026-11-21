package com.passpace.client;

import com.passpace.error.exception.CollectException;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.passpace.dto.collect.CollectDtos.ExamScheduleItem;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * [용성] 공공데이터포털 국가자격 시험일정 조회 API(15074408) 호출.
 *  - 인증키(passpace.collect.data-go-kr-key)가 없으면 → 샘플 파일(collect/sample_exam_schedule.json) 사용
 *  - resultCode 99(큐넷 일시 오류)는 3초 간격 최대 3회 재시도
 *  - HTTP 403 은 "활용신청 승인 직후 키 반영 대기"인 경우가 많다 → 그대로 기록하고 중단
 */
@Component
public class DataGoKrExamClient {

    private static final Logger log = LoggerFactory.getLogger(DataGoKrExamClient.class);
    private static final String URL = "https://apis.data.go.kr/B490007/qualExamSchd/getQualExamSchdList";

    private final RestClient restClient = RestClient.create();
    private final ObjectMapper objectMapper;
    private final ExamScheduleJsonParser parser = new ExamScheduleJsonParser();
    private final String serviceKey;

    public DataGoKrExamClient(ObjectMapper objectMapper,
                              @Value("${passpace.collect.data-go-kr-key:}") String serviceKey) {
        this.objectMapper = objectMapper;
        this.serviceKey = serviceKey == null ? "" : serviceKey.trim();
    }

    public boolean hasKey() {
        return !serviceKey.isEmpty();
    }

    /** 실제 API 호출 */
    public List<ExamScheduleItem> fetch(int year, String jmCd) {
        // 인증키에 + / = 가 들어 있어 직접 인코딩해서 주소를 만든다 (이중 인코딩 방지)
        URI uri = URI.create(URL
                + "?serviceKey=" + URLEncoder.encode(serviceKey, StandardCharsets.UTF_8)
                + "&numOfRows=50&pageNo=1&dataFormat=json"
                + "&implYy=" + year
                + "&qualgbCd=T"
                + "&jmCd=" + jmCd);

        CollectException last = null;
        for (int attempt = 1; attempt <= 3; attempt++) {
            try {
                String body = restClient.get().uri(uri).retrieve().body(String.class);
                JsonNode root = objectMapper.readTree(body);
                parser.checkResultCode(root);
                return parser.parse(root);
            } catch (HttpClientErrorException e) {
                // 403·401 등은 재시도해도 같은 결과 → 바로 중단
                throw new CollectException("HTTP_" + e.getStatusCode().value(),
                        "API 접근 거부(" + e.getStatusCode().value() + "). 활용신청 승인 직후라면 키 반영까지 기다리세요.");
            } catch (CollectException e) {
                last = e;
                if (!"API_RESULT_99".equals(e.getFailType())) {
                    throw e;
                }
                log.warn("큐넷 일시 오류(99) - {}회째, 3초 후 재시도", attempt);
            } catch (IOException e) {
                last = new CollectException("PARSE_ERROR", "응답을 JSON 으로 읽지 못했습니다: " + e.getMessage());
            } catch (Exception e) {
                last = new CollectException("NETWORK", "API 호출 실패: " + e.getMessage());
                log.warn("API 호출 실패 {}회째: {}", attempt, e.getMessage());
            }
            sleep(3000);
        }
        throw last;
    }

    /** 키가 없을 때 쓰는 샘플 (실제 일정 아님) */
    public List<ExamScheduleItem> readSample() {
        try (InputStream in = new ClassPathResource("collect/sample_exam_schedule.json").getInputStream()) {
            return parser.parse(objectMapper.readTree(in));
        } catch (IOException e) {
            throw new CollectException("SAMPLE_ERROR", "샘플 파일을 읽지 못했습니다: " + e.getMessage());
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
