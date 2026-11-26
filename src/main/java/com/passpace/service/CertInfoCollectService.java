package com.passpace.service;

import com.passpace.client.DataGoKrExamClient;
import com.passpace.constant.CollectSources;
import com.passpace.dto.collect.CollectDtos.ExamScheduleItem;
import com.passpace.repository.ExamRoundRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.passpace.constant.ExamType;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.math.BigDecimal;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [11-26] 자격증 정보 메뉴 값 수집 (관리자 실행). 수집이 되는 값만 덮어쓰고, 안 되는 값은 db/14 의 고정값을 그대로 둔다.
 *
 *  1) 큐넷 국가자격 종목별 자격정보 API(15003003) "취득방법" → 검정방법(문항 수·시간)·합격기준  [정보처리기사, 산업안전기사]
 *  2) 큐넷 연도별 회별 합격률 API(15089380, 기사 grdCd=30) → EXAM_ROUNDS 접수자·합격자·합격률 (최근 3년 + 올해) [정보처리기사, 산업안전기사]
 *  3) 국가자격 시험일정 API(15074408) → 산업안전기사(jmCd 1431) 회차 일정 (정보처리기사는 기존 시험일정 수집이 담당)
 *  4) 데이터 자격검정 시험 정보 API(15062838, SQLD 일정과 같은 파일) → 빅데이터분석기사 필기·실기 일정
 *  수집 안 됨 → 고정값 유지: 응시료(큐넷 수수료 화면이 검색 후 클릭해야 나옴), SQLD·ADsP·컴활·전산회계(공공 API 없음)
 *
 *  실행: 관리자 API POST /admin/collect/cert-info, 또는 collect-data/certinfo/collect.txt 파일(내용 무관)
 *  결과: collect-data/certinfo/collect-result.txt
 */
@Service
public class CertInfoCollectService {

    private static final Logger log = LoggerFactory.getLogger(CertInfoCollectService.class);

    /** CERTIFICATIONS.source_exam_code → 큐넷 종목코드(jmCd). 2026-11-26 합격률 API 응답으로 확인 */
    static final Map<String, String> QNET_JMCD = new LinkedHashMap<>();

    static {
        QNET_JMCD.put("1320", "1320");     // 정보처리기사
        QNET_JMCD.put("SAFETY", "1431");   // 산업안전기사
    }

    private static final String INFO_URL = "http://openapi.q-net.or.kr/api/service/rest/InquiryInformationTradeNTQSVC/getList";
    private static final String PASS_RATE_URL = "http://openapi.q-net.or.kr/api/service/rest/InquiryQualPassRateSVC/getList";
    /** 합격률 API 등급코드: 10 기술사, 20 기능장, 30 기사 */
    private static final String GRADE_ENGINEER = "30";

    private final JdbcTemplate jdbc;
    private final DataGoKrExamClient scheduleClient;
    private final ExamRoundRepository examRounds;
    private final SqldScheduleCollectService dataqSchedule;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final String serviceKey;
    private final Path dir;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(15)).build();

    public CertInfoCollectService(JdbcTemplate jdbc, DataGoKrExamClient scheduleClient, ExamRoundRepository examRounds,
                                  SqldScheduleCollectService dataqSchedule,
                                  @Value("${passpace.collect.data-go-kr-key:}") String serviceKey,
                                  @Value("${passpace.collect.data-dir:collect-data}") String dataDir) {
        this.jdbc = jdbc;
        this.scheduleClient = scheduleClient;
        this.examRounds = examRounds;
        this.dataqSchedule = dataqSchedule;
        this.serviceKey = serviceKey == null ? "" : serviceKey.trim();
        this.dir = Paths.get(dataDir).toAbsolutePath().normalize().resolve("certinfo");
    }

    /** 수집 실행. 결과 줄 목록 (파일에도 저장) */
    public synchronized List<String> collect() {
        List<String> out = new ArrayList<>();
        out.add("# 자격증 정보 수집 " + LocalDateTime.now());
        if (serviceKey.isEmpty()) {
            out.add("공공데이터 인증키(passpace.collect.data-go-kr-key)가 없어 수집하지 않음 → db/14 고정값 유지");
            save(out);
            return out;
        }
        for (Map.Entry<String, String> e : QNET_JMCD.entrySet()) {
            Long certId = certId(e.getKey());
            if (certId == null) {
                out.add(e.getKey() + ": CERTIFICATIONS 에 없음 (db/13 실행 필요) → 건너뜀");
                continue;
            }
            out.add(step(() -> collectQualInfo(certId, e.getKey(), e.getValue())));
        }
        out.add(step(this::collectPassRates));
        Long safety = certId("SAFETY");
        if (safety != null) out.add(step(() -> collectSchedule(safety, "SAFETY", QNET_JMCD.get("SAFETY"))));
        Long bigdata = certId("BIGDATA");
        if (bigdata != null) out.add(step(() -> collectBigDataSchedule(bigdata)));
        out.add("고정값 유지: 응시료 전체, SQLD·ADsP·컴활 1·2급·빅분기 시험 정보, 전산회계 일정·시험 정보 (공식 수집 경로 없음)");
        save(out);
        return out;
    }

    // ---------------------------------------------------------------------
    // 1) 자격정보 API → 검정방법·합격기준

    String collectQualInfo(long certId, String code, String jmCd) throws IOException, InterruptedException {
        String xml = get(INFO_URL + "?serviceKey=" + key() + "&jmCd=" + jmCd);
        QualInfo q = parseQualInfo(xml);
        if (q == null) return code + " 자격정보: 취득방법 항목 없음 → 고정값 유지";
        int n = 0;
        n += updateExamInfo(certId, "WRITTEN", q.writtenMethod, q.writtenCriteria, q.writtenQuestions, q.writtenMinutes);
        n += updateExamInfo(certId, "PRACTICAL", q.practicalMethod, q.practicalCriteria, null, q.practicalMinutes);
        jdbc.update("UPDATE CERTIFICATION_INFO SET info_verified_at = ? WHERE certification_id = ?", LocalDate.now(), certId);
        return code + " 자격정보: 필기 [" + q.writtenMethod + " / " + q.writtenQuestions + "문항 · " + q.writtenMinutes + "분 / "
                + q.writtenCriteria + "], 실기 [" + q.practicalMethod + " / " + q.practicalMinutes + "분 / " + q.practicalCriteria
                + "] → " + n + "행 갱신";
    }

    private int updateExamInfo(long certId, String type, String method, String criteria, Integer questions, Integer minutes) {
        if (method == null && criteria == null) return 0;
        // 수집한 값만 덮어쓴다 (null 은 기존 값 유지)
        return jdbc.update("""
                UPDATE CERTIFICATION_EXAM_INFO
                   SET exam_method = COALESCE(?, exam_method), pass_criteria = COALESCE(?, pass_criteria),
                       question_count = COALESCE(?, question_count), duration_minutes = COALESCE(?, duration_minutes)
                 WHERE certification_id = ? AND exam_type = ?
                """, method, criteria, questions, minutes, certId, type);
    }

    /** "취득방법" 본문에서 시험과목 수·검정방법·합격기준을 읽는다 */
    static QualInfo parseQualInfo(String xml) {
        Matcher m = Pattern.compile("<item><contents>((?:(?!</contents>).)*)</contents><infogb>취득방법</infogb>", Pattern.DOTALL).matcher(xml);
        if (!m.find()) return null;
        String text = unescape(unescape(m.group(1))).replace("\r", "");
        String subjects = section(text, "시험과목", "검정방법");
        String method = section(text, "검정방법", "합격기준");
        String criteria = section(text, "합격기준", null);
        QualInfo q = new QualInfo();
        int subjectCount = 0;
        String writtenSubjects = line(subjects, "필기");
        if (writtenSubjects != null) {
            Matcher s = Pattern.compile("(\\d+)\\s*\\.").matcher(writtenSubjects);
            while (s.find()) subjectCount++;
        }
        q.writtenMethod = line(method, "필기");
        q.practicalMethod = line(method, "실기");
        q.writtenCriteria = tidyCriteria(line(criteria, "필기"));
        q.practicalCriteria = tidyCriteria(line(criteria, "실기"));
        if (q.writtenMethod != null) {
            Matcher per = Pattern.compile("과목당\\s*(\\d+)\\s*문항\\s*\\(\\s*과목당\\s*(\\d+)\\s*분").matcher(q.writtenMethod);
            if (per.find() && subjectCount > 0) {
                q.writtenQuestions = Integer.parseInt(per.group(1)) * subjectCount;
                q.writtenMinutes = Integer.parseInt(per.group(2)) * subjectCount;
            }
            q.writtenMethod = q.writtenMethod.replaceAll("[,\\s]*과목당.*$", "").trim();
            if (subjectCount > 0) q.writtenMethod = q.writtenMethod + " (" + subjectCount + "과목)";
        }
        if (q.practicalMethod != null && !q.practicalMethod.contains("+")) {
            q.practicalMinutes = minutes(q.practicalMethod);
        }
        return q;
    }

    static final class QualInfo {
        String writtenMethod, practicalMethod, writtenCriteria, practicalCriteria;
        Integer writtenQuestions, writtenMinutes, practicalMinutes;
    }

    /** "2시간30분" → 150, "1시간 정도" → 60 */
    static Integer minutes(String s) {
        Matcher m = Pattern.compile("(\\d+)\\s*시간\\s*(?:(\\d+)\\s*분)?").matcher(s);
        if (m.find()) return Integer.parseInt(m.group(1)) * 60 + (m.group(2) == null ? 0 : Integer.parseInt(m.group(2)));
        m = Pattern.compile("(\\d+)\\s*분").matcher(s);
        return m.find() ? Integer.parseInt(m.group(1)) : null;
    }

    private static String tidyCriteria(String s) {
        if (s == null) return null;
        return s.replace("100점을 만점으로 하여", "").replace("전과목", "전 과목").replaceAll("\\.$", "").trim();
    }

    /** start 제목 다음부터 end 제목 전까지 */
    private static String section(String text, String start, String end) {
        int i = text.indexOf(start);
        if (i < 0) return "";
        int j = end == null ? -1 : text.indexOf(end, i + start.length());
        return text.substring(i + start.length(), j < 0 ? text.length() : j);
    }

    /** "- 필기 : 내용" 줄의 내용 (콜론 없어도 됨) */
    private static String line(String block, String label) {
        Matcher m = Pattern.compile("-\\s*" + label + "\\s*:?\\s*(.+)").matcher(block);
        return m.find() ? m.group(1).trim() : null;
    }

    // ---------------------------------------------------------------------
    // 2) 합격률 API → EXAM_ROUNDS

    String collectPassRates() throws IOException, InterruptedException {
        int now = LocalDate.now().getYear();
        int saved = 0, inserted = 0;
        Map<String, Long> certByJm = new LinkedHashMap<>();
        QNET_JMCD.forEach((code, jm) -> {
            Long id = certId(code);
            if (id != null) certByJm.put(jm, id);
        });
        for (int y = now - 3; y <= now; y++) {
            String xml = get(PASS_RATE_URL + "?serviceKey=" + key() + "&baseYY=" + y + "&grdCd=" + GRADE_ENGINEER + "&numOfRows=1000");
            for (PassRateRow r : parsePassRates(xml)) {
                Long certId = certByJm.get(r.jmCd);
                if (certId == null) continue;
                List<Long> ids = jdbc.queryForList("""
                        SELECT exam_round_id FROM EXAM_ROUNDS
                        WHERE certification_id = ? AND exam_year = ? AND round_no = ? AND exam_type = ?
                        """, Long.class, certId, r.year, r.round, r.examType);
                if (ids.isEmpty()) {
                    jdbc.update("""
                            INSERT INTO EXAM_ROUNDS (certification_id, source_id, source_exam_code, exam_year, round_no, exam_type,
                                                     applicant_count, pass_count, pass_rate, last_synced_at)
                            VALUES (?, NULL, ?, ?, ?, ?, ?, ?, ?, NOW())
                            """, certId, codeOf(certId), r.year, r.round, r.examType, r.applicants, r.passed, r.rate);
                    inserted++;
                } else {
                    jdbc.update("UPDATE EXAM_ROUNDS SET applicant_count = ?, pass_count = ?, pass_rate = ? WHERE exam_round_id = ?",
                            r.applicants, r.passed, r.rate, ids.get(0));
                }
                saved++;
            }
        }
        return "합격률: " + (now - 3) + "~" + now + "년 기사 회차 " + saved + "건 저장 (새 회차 행 " + inserted + "건)";
    }

    record PassRateRow(String jmCd, int year, int round, String examType, Integer applicants, Integer passed, BigDecimal rate) {
    }

    static List<PassRateRow> parsePassRates(String xml) {
        List<PassRateRow> rows = new ArrayList<>();
        Matcher it = Pattern.compile("<item>(.*?)</item>", Pattern.DOTALL).matcher(xml);
        while (it.find()) {
            Map<String, String> f = new LinkedHashMap<>();
            Matcher kv = Pattern.compile("<(\\w+)>([^<]*)</\\1>").matcher(it.group(1));
            while (kv.find()) f.put(kv.group(1), kv.group(2).trim());
            String type = "필기".equals(f.get("examTypCcd")) ? "WRITTEN" : "실기".equals(f.get("examTypCcd")) ? "PRACTICAL" : null;
            if (type == null || f.get("jmCd") == null) continue;
            try {
                String rate = f.getOrDefault("passRate", "").replace("%", "").trim();
                rows.add(new PassRateRow(f.get("jmCd"), Integer.parseInt(f.get("implYy")), Integer.parseInt(f.get("implSeq")), type,
                        intOrNull(f.get("recptNoCnt")), intOrNull(f.get("examPassCnt")), rate.isEmpty() ? null : new BigDecimal(rate)));
            } catch (NumberFormatException ignored) {
            }
        }
        return rows;
    }

    // ---------------------------------------------------------------------
    // 3) 산업안전기사 시험일정

    String collectSchedule(long certId, String code, String jmCd) {
        int year = LocalDate.now().getYear();
        List<ExamScheduleItem> items = new ArrayList<>();
        for (int y = year; y <= year + 1; y++) {
            try {
                items.addAll(scheduleClient.fetch(y, jmCd));
            } catch (Exception e) {
                if (y == year) return code + " 일정: 조회 실패 " + e.getMessage();
            }
        }
        int saved = 0;
        for (ExamScheduleItem item : items) {
            var stored = examRounds.find(certId, item.examYear(), item.roundNo(), item.examType().name());
            if (stored.isEmpty()) examRounds.insert(certId, CollectSources.EXAM_SCHEDULE_API, code, item);
            else examRounds.update(stored.get().examRoundId(), CollectSources.EXAM_SCHEDULE_API, item);
            saved++;
        }
        return code + " 일정: " + saved + "개 회차 저장";
    }

    // ---------------------------------------------------------------------
    // 4) 빅데이터분석기사 일정 (데이터 자격검정 시험 정보 API, SQLD 일정과 같은 파일)

    String collectBigDataSchedule(long certId) throws IOException {
        String body = dataqSchedule.latestRawData();
        if (body == null) return "BIGDATA 일정: 인증키 없음 → 고정값 유지";
        List<ExamScheduleItem> items = parseBigData(objectMapper.readTree(body), LocalDate.now().minusYears(1));
        if (items.isEmpty()) return "BIGDATA 일정: 공공 API 파일에 빅데이터분석기사 회차 없음 → 고정값 유지";
        int saved = 0;
        for (ExamScheduleItem item : items) {
            var stored = examRounds.find(certId, item.examYear(), item.roundNo(), item.examType().name());
            if (stored.isEmpty()) examRounds.insert(certId, CollectSources.SQLD_SCHEDULE_API, "BIGDATA", item);
            else examRounds.update(stored.get().examRoundId(), CollectSources.SQLD_SCHEDULE_API, item);
            saved++;
        }
        return "BIGDATA 일정: " + saved + "개 회차 저장";
    }

    /** 시험명에 빅데이터분석기사가 들어간 행 → 필기/실기 회차 (시험명에 "실기"가 있으면 실기) */
    static List<ExamScheduleItem> parseBigData(JsonNode root, LocalDate from) {
        List<ExamScheduleItem> items = new ArrayList<>();
        JsonNode data = root.path("data");
        if (!data.isArray()) return items;
        Map<String, ExamScheduleItem> seen = new LinkedHashMap<>();
        for (JsonNode d : data) {
            String name = d.path("시험명").asText("");
            if (!name.replace(" ", "").contains("빅데이터분석기사")) continue;
            LocalDate exam = day(d.path("시험일").asText(""));
            int round = d.path("회차").asInt(-1);
            if (exam == null || round < 0 || exam.isBefore(from)) continue;
            ExamType type = name.contains("실기") ? ExamType.PRACTICAL : ExamType.WRITTEN;
            seen.putIfAbsent(round + type.name(), new ExamScheduleItem(exam.getYear(), round, type,
                    day(d.path("접수시작일").asText("")), day(d.path("접수마감일").asText("")), exam, exam,
                    day(d.path("합격자발표일").asText("")), "빅데이터분석기사 제" + round + "회 " + type.getLabel()));
        }
        items.addAll(seen.values());
        return items;
    }

    /** "2026-11-28", "2026.11.28", "20261128" → 날짜 */
    static LocalDate day(String s) {
        String d = s == null ? "" : s.replaceAll("[^0-9]", "");
        if (d.length() < 8) return null;
        try {
            return LocalDate.of(Integer.parseInt(d.substring(0, 4)), Integer.parseInt(d.substring(4, 6)), Integer.parseInt(d.substring(6, 8)));
        } catch (Exception e) {
            return null;
        }
    }

    // ---------------------------------------------------------------------

    private interface Step {
        String run() throws Exception;
    }

    private static String step(Step s) {
        try {
            return s.run();
        } catch (Exception e) {
            log.warn("자격증 정보 수집 실패: {}", e.getMessage());
            return "실패: " + e.getMessage() + " → 고정값 유지";
        }
    }

    private Long certId(String code) {
        List<Long> ids = jdbc.queryForList("SELECT certification_id FROM CERTIFICATIONS WHERE source_exam_code = ?", Long.class, code);
        return ids.isEmpty() ? null : ids.get(0);
    }

    private String codeOf(long certId) {
        return jdbc.queryForObject("SELECT source_exam_code FROM CERTIFICATIONS WHERE certification_id = ?", String.class, certId);
    }

    private String key() {
        return URLEncoder.encode(serviceKey, StandardCharsets.UTF_8);
    }

    private String get(String url) throws IOException, InterruptedException {
        HttpRequest req = HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofSeconds(30))
                .header("User-Agent", "PasspaceStudentBot/0.1 (school project, non-commercial)").GET().build();
        HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        if (res.statusCode() != 200) throw new IOException("HTTP " + res.statusCode());
        return res.body();
    }

    private static Integer intOrNull(String s) {
        try {
            return s == null || s.isBlank() ? null : Integer.parseInt(s.replace(",", "").trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    static String unescape(String s) {
        return s.replace("&#xD;", "").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
                .replace("&#39;", "'").replace("&amp;", "&");
    }

    private void save(List<String> lines) {
        try {
            Files.createDirectories(dir);
            Files.write(dir.resolve("collect-result.txt"), lines, StandardCharsets.UTF_8);
        } catch (IOException e) {
            log.warn("수집 결과 파일 저장 실패: {}", e.getMessage());
        }
        lines.forEach(l -> log.info("자격증 정보 수집: {}", l));
    }

    /** collect-data/certinfo/collect.txt 가 생기면 한 번 실행 (토큰 없이 실행하기 위함) */
    @EventListener(ApplicationReadyEvent.class)
    public void startTriggerWatcher() {
        Thread w = new Thread(() -> {
            Path trigger = dir.resolve("collect.txt");
            while (true) {
                try {
                    Thread.sleep(10_000L);
                    if (Files.exists(trigger)) {
                        Files.move(trigger, trigger.resolveSibling("collect.done"), StandardCopyOption.REPLACE_EXISTING);
                        collect();
                    }
                } catch (InterruptedException e) {
                    return;
                } catch (Exception e) {
                    log.warn("자격증 정보 수집 신호 처리 실패: {}", e.getMessage());
                }
            }
        }, "certinfo-collect-trigger");
        w.setDaemon(true);
        w.start();
    }
}
