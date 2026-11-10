package com.passpace.collect.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.passpace.collect.CollectSources;
import com.passpace.collect.client.CollectException;
import com.passpace.collect.dto.CollectDtos.CollectResult;
import com.passpace.collect.dto.CollectDtos.ExamScheduleItem;
import com.passpace.collect.repository.ExamRoundRepository;
import com.passpace.collect.repository.ExamRoundRepository.StoredRound;
import com.passpace.collect.repository.SyncJobRepository;
import com.passpace.common.code.ExamType;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

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
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [용성] SQLD 시험일정 수집 - 공공데이터포털 "한국데이터산업진흥원_데이터 자격검정 시험 정보"(15062838) API
 *
 *  - 공식 기관 공공데이터 API (인증키는 정처기 일정 API 와 같은 passpace.collect.data-go-kr-key)
 *  - 파일데이터형이라 해마다 새 파일(uddi)이 추가된다 → API 문서(Swagger)에서 가장 최근 파일을 자동 선택
 *  - 응답에 2010년부터의 SQLD·SQLP·DAP 등이 섞여 있어
 *    시험명 "SQLD" + 시험구분 "일반검정" + 최근 2년 회차만 EXAM_ROUNDS 에 저장 (같은 회차 중복 행은 1개로)
 *
 * 응답 항목: 순번, 시험명, 시험구분, 회차, 시험일, 시험시작시간, 접수시작일, 접수마감일, 시험장소, 합격자발표일, 시험유형
 */
@Service
public class SqldScheduleCollectService {

    private static final Logger log = LoggerFactory.getLogger(SqldScheduleCollectService.class);
    private static final String SQLD_CODE = "SQLD";
    private static final String DOCS_URL = "https://infuser.odcloud.kr/oas/docs?namespace=15062838/v1";
    private static final String API_BASE = "https://api.odcloud.kr/api";
    /** Swagger summary 끝의 파일 날짜: "..._20260106" */
    private static final Pattern FILE_DATE = Pattern.compile("_(\\d{8})\\s*$");

    private final ExamRoundRepository examRoundRepository;
    private final SyncJobRepository syncJobRepository;
    private final ObjectMapper objectMapper;
    private final String serviceKey;
    private final HttpClient http = HttpClient.newBuilder()
            .version(HttpClient.Version.HTTP_1_1)
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    public SqldScheduleCollectService(ExamRoundRepository examRoundRepository, SyncJobRepository syncJobRepository,
                                      ObjectMapper objectMapper,
                                      @Value("${passpace.collect.data-go-kr-key:}") String serviceKey) {
        this.examRoundRepository = examRoundRepository;
        this.syncJobRepository = syncJobRepository;
        this.objectMapper = objectMapper;
        this.serviceKey = serviceKey == null ? "" : serviceKey.trim();
    }

    public synchronized CollectResult collect() {
        String mode = "API(15062838 데이터 자격검정 시험 정보)";
        if (serviceKey.isEmpty()) {
            return new CollectResult("SQLD_SCHEDULE", mode, 0, 0, 0, "SKIPPED",
                    "application-local.yml 에 data-go-kr-key 가 없습니다. 공공데이터포털 15062838 활용신청 후 같은 인증키를 쓰면 됩니다.");
        }
        long certId = examRoundRepository.findCertificationId(SQLD_CODE)
                .orElseThrow(() -> new IllegalStateException("CERTIFICATIONS 에 SQLD 가 없습니다 (db/03_seed.sql)."));

        long jobId = syncJobRepository.start(CollectSources.SQLD_SCHEDULE_API, "SQLD_SCHEDULE");
        int success = 0, skipped = 0;
        try {
            String path = latestFilePath();
            List<ExamScheduleItem> items = parse(get(API_BASE + path + "?page=1&perPage=1000&returnType=JSON&serviceKey="
                    + URLEncoder.encode(serviceKey, StandardCharsets.UTF_8)), LocalDate.now().minusYears(2));
            if (items.isEmpty()) {
                syncJobRepository.finish(jobId, 0, 0, 0, "FAILED", "EMPTY_RESULT", "SQLD 회차 0건 - 기존 데이터 유지");
                return new CollectResult("SQLD_SCHEDULE", mode, 0, 0, 0, "FAILED", "SQLD 회차가 0건입니다. 기존 데이터를 유지합니다.");
            }
            for (ExamScheduleItem item : items) {
                var stored = examRoundRepository.find(certId, item.examYear(), item.roundNo(), item.examType().name());
                if (stored.isEmpty()) {
                    examRoundRepository.insert(certId, CollectSources.SQLD_SCHEDULE_API, SQLD_CODE, item);
                    success++;
                } else {
                    String changed = changedFields(stored.get(), item);
                    if (changed == null) {
                        examRoundRepository.touch(stored.get().examRoundId());
                        skipped++;
                    } else {
                        examRoundRepository.insertChangeLog(stored.get().examRoundId(), jobId, stored.get(), item, changed);
                        examRoundRepository.update(stored.get().examRoundId(), CollectSources.SQLD_SCHEDULE_API, item);
                        success++;
                    }
                }
            }
            syncJobRepository.finish(jobId, success, 0, skipped, "SUCCESS", null, null);
            ExamScheduleItem last = items.get(items.size() - 1);
            return new CollectResult("SQLD_SCHEDULE", mode, success, 0, skipped, "SUCCESS",
                    "SQLD " + items.size() + "개 회차(최근 2년): 저장·변경 " + success + "건, 변경 없음 " + skipped
                            + "건 / 가장 최근 제" + last.roundNo() + "회 시험일 " + last.examStart());
        } catch (CollectException e) {
            syncJobRepository.finish(jobId, success, 0, skipped, "FAILED", e.getFailType(), e.getMessage());
            return new CollectResult("SQLD_SCHEDULE", mode, success, 0, skipped, "FAILED", e.getMessage());
        }
    }

    /** API 문서에서 summary 날짜(_YYYYMMDD)가 가장 늦은 데이터 파일 경로 */
    String latestFilePath() {
        JsonNode docs = readJson(get(DOCS_URL));
        String best = null, bestDate = "";
        for (Iterator<Map.Entry<String, JsonNode>> it = docs.path("paths").fields(); it.hasNext(); ) {
            Map.Entry<String, JsonNode> e = it.next();
            Matcher m = FILE_DATE.matcher(e.getValue().path("get").path("summary").asText(""));
            String date = m.find() ? m.group(1) : "";
            if (best == null || date.compareTo(bestDate) > 0) {
                best = e.getKey();
                bestDate = date;
            }
        }
        if (best == null) throw new CollectException("PARSE_ERROR", "API 문서에서 데이터 파일 경로를 찾지 못했습니다.");
        log.info("SQLD 일정 API 파일 선택: {} ({})", best, bestDate);
        return best;
    }

    /** 응답 JSON → SQLD 일반검정 회차 (from 이후, 회차별 1건, 시험일 순) */
    List<ExamScheduleItem> parse(String body, LocalDate from) {
        JsonNode data = readJson(body).path("data");
        if (!data.isArray()) return List.of();
        Map<Integer, ExamScheduleItem> byRound = new LinkedHashMap<>();
        for (JsonNode d : data) {
            if (!d.path("시험명").asText("").contains("SQLD")) continue;
            if (!"일반검정".equals(d.path("시험구분").asText(""))) continue;
            LocalDate exam = date(d.path("시험일").asText(""));
            int round = d.path("회차").asInt(-1);
            if (exam == null || round < 0 || exam.isBefore(from)) continue;
            byRound.putIfAbsent(round, new ExamScheduleItem(exam.getYear(), round, ExamType.WRITTEN,
                    date(d.path("접수시작일").asText("")), date(d.path("접수마감일").asText("")),
                    exam, exam, date(d.path("합격자발표일").asText("")),
                    "SQLD 제" + round + "회"));
        }
        List<ExamScheduleItem> items = new ArrayList<>(byRound.values());
        items.sort((a, b) -> a.examStart().compareTo(b.examStart()));
        return items;
    }

    private String get(String url) {
        HttpRequest req = HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofSeconds(30))
                .header("Accept", "application/json").GET().build();
        try {
            HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            if (res.statusCode() == 401 || res.statusCode() == 403) {
                throw new CollectException("HTTP_" + res.statusCode(),
                        "인증 실패(" + res.statusCode() + "). 공공데이터포털 15062838 활용신청 승인 여부와 인증키를 확인하세요.");
            }
            if (res.statusCode() >= 400) {
                throw new CollectException("HTTP_" + res.statusCode(), "API 호출 실패(" + res.statusCode() + ")");
            }
            return res.body();
        } catch (IOException e) {
            throw new CollectException("NETWORK", "API 연결 실패: " + e.getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new CollectException("NETWORK", "요청이 중단되었습니다");
        }
    }

    private JsonNode readJson(String body) {
        try {
            return objectMapper.readTree(body);
        } catch (IOException e) {
            throw new CollectException("PARSE_ERROR", "응답을 JSON 으로 읽지 못했습니다: " + e.getMessage());
        }
    }

    private static LocalDate date(String s) {
        if (s == null || s.length() < 10) return null;
        try {
            return LocalDate.parse(s.substring(0, 10).replace('.', '-'));
        } catch (Exception e) {
            return null;
        }
    }

    private static String changedFields(StoredRound b, ExamScheduleItem a) {
        List<String> c = new ArrayList<>();
        if (!Objects.equals(b.regStart(), a.regStart())) c.add("\"reg_start_at\"");
        if (!Objects.equals(b.regEnd(), a.regEnd())) c.add("\"reg_end_at\"");
        if (!Objects.equals(b.examStart(), a.examStart())) c.add("\"exam_start_date\"");
        if (!Objects.equals(b.resultDate(), a.resultDate())) c.add("\"result_date\"");
        return c.isEmpty() ? null : "[" + String.join(",", c) + "]";
    }
}
