package com.passpace.client;

import com.passpace.error.exception.CollectException;

import com.fasterxml.jackson.databind.JsonNode;
import com.passpace.dto.collect.CollectDtos.ExamScheduleItem;
import com.passpace.constant.ExamType;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

/**
 * [용성] 국가자격 시험일정 API(15074408) JSON 응답 → ExamScheduleItem 목록.
 *
 * 응답 항목 (공공데이터포털 명세)
 *   implYy 시행년도, implSeq 시행회차, description 설명,
 *   docRegStartDt/docRegEndDt 필기 원서접수, docExamStartDt 필기 시작일 ...  (명세에서 확인됨)
 *   확인 필요: docExamEndDt, docPassDt, pracRegStartDt, pracRegEndDt, pracExamStartDt, pracExamEndDt, pracPassDt
 *            → 실제 응답을 한 번 출력해 보고 이름이 다르면 아래 상수만 고친다.
 *
 * 응답 JSON 의 감싸는 구조(response/body/items/item 등)가 바뀌어도 동작하도록,
 * "implSeq 를 가진 객체"를 트리 전체에서 찾아 쓴다.
 */
public class ExamScheduleJsonParser {

    private static final DateTimeFormatter YMD = DateTimeFormatter.ofPattern("yyyyMMdd");

    // 필기(doc) / 실기(prac) 필드 이름
    private static final String[] WRITTEN = {"docRegStartDt", "docRegEndDt", "docExamStartDt", "docExamEndDt", "docPassDt"};
    private static final String[] PRACTICAL = {"pracRegStartDt", "pracRegEndDt", "pracExamStartDt", "pracExamEndDt", "pracPassDt"};

    /** resultCode 가 "00" 이 아니면 예외 (99 = 큐넷 서버 일시 오류) */
    public void checkResultCode(JsonNode root) {
        JsonNode code = root.findValue("resultCode");
        if (code != null && !"00".equals(code.asText()) && !"0".equals(code.asText())) {
            JsonNode msg = root.findValue("resultMsg");
            throw new CollectException("API_RESULT_" + code.asText(),
                    "API 오류 " + code.asText() + " : " + (msg == null ? "" : msg.asText()));
        }
    }

    public List<ExamScheduleItem> parse(JsonNode root) {
        List<JsonNode> rows = new ArrayList<>();
        collectRows(root, rows);

        List<ExamScheduleItem> items = new ArrayList<>();
        for (JsonNode row : rows) {
            int year = row.path("implYy").asInt(0);
            int round = row.path("implSeq").asInt(0);
            String desc = row.path("description").asText("");
            if (year == 0 || round == 0) {
                continue;
            }
            addIfPresent(items, row, year, round, ExamType.WRITTEN, WRITTEN, desc);
            addIfPresent(items, row, year, round, ExamType.PRACTICAL, PRACTICAL, desc);
        }
        return items;
    }

    private void addIfPresent(List<ExamScheduleItem> items, JsonNode row, int year, int round,
                              ExamType type, String[] f, String desc) {
        LocalDate examStart = date(row, f[2]);
        if (examStart == null) {
            return;     // 시험일이 없으면 저장하지 않는다 (기획안 7.2.3: 불확실한 일정은 저장 안 함)
        }
        LocalDate examEnd = date(row, f[3]);
        items.add(new ExamScheduleItem(year, round, type,
                date(row, f[0]), date(row, f[1]),
                examStart, examEnd == null ? examStart : examEnd,
                date(row, f[4]), desc));
    }

    /** 트리 전체에서 implSeq 를 가진 객체만 모은다 */
    private void collectRows(JsonNode node, List<JsonNode> out) {
        if (node == null) {
            return;
        }
        if (node.isObject() && node.has("implSeq")) {
            out.add(node);
            return;
        }
        if (node.isContainerNode()) {
            for (JsonNode child : node) {
                collectRows(child, out);
            }
        }
    }

    /** "20270207" → LocalDate. 비었거나 형식이 다르면 null */
    static LocalDate date(JsonNode row, String field) {
        String v = row.path(field).asText("").trim();
        if (v.length() != 8) {
            return null;
        }
        try {
            return LocalDate.parse(v, YMD);
        } catch (Exception e) {
            return null;
        }
    }
}
