package com.passpace.chat.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.passpace.chat.client.OllamaClient;
import com.passpace.chat.dto.ChatDtos.ExtractedCondition;
import com.passpace.common.code.ExamType;
import com.passpace.common.code.MajorType;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * [동건] 처리 ① 조건 추출
 *  1) 정규식(RegexConditionParser)으로 이번 질문에서 먼저 뽑는다 → 빠르고 결과가 항상 같다
 *  2) 빠진 값은 같은 대화방의 앞 질문들(최근 것부터)에서 정규식으로 채운다
 *     예) "3월 20일 필기, 하루 2시간" → 다음 질문 "하루 3시간이면?" 은 시험일을 앞 질문에서 가져온다
 *  3) 시험일·하루 시간이 그래도 없고 이번 질문에 그 값의 단서가 있으면 LLM(1차 호출, JSON 스키마 강제)으로 다시 읽는다
 *     LLM 값은 질문에 그 값의 단서가 있을 때만 받는다 (예: "시간"·"분"이 없는데 하루 시간이 나오면 버림)
 *     → LLM 이 지어낸 값이 마이페이지 값보다 앞서는 일을 막는다
 *  4) LLM 결과도 Java 가 다시 검증한다 (날짜 형식·지난 날짜, 하루 0.5~16시간)
 */
@Component
public class ConditionExtractor {

    private static final Logger log = LoggerFactory.getLogger(ConditionExtractor.class);

    private final RegexConditionParser regexParser = new RegexConditionParser();
    private final OllamaClient ollama;
    private final ObjectMapper objectMapper;
    private final String systemPromptTemplate;

    public ConditionExtractor(OllamaClient ollama, ObjectMapper objectMapper) throws IOException {
        this.ollama = ollama;
        this.objectMapper = objectMapper;
        this.systemPromptTemplate = new ClassPathResource("prompts/chat_condition_system.txt")
                .getContentAsString(StandardCharsets.UTF_8);
    }

    /**
     * @param message         이번 질문
     * @param previousMessages 같은 대화방의 앞 질문 (최근 것부터, 없으면 빈 목록)
     */
    public ExtractedCondition extract(String message, List<String> previousMessages, LocalDate today) {
        ExtractedCondition current = regexParser.parse(message, today);
        ExtractedCondition combined = current;
        if (previousMessages != null) {
            for (String previous : previousMessages) {
                if (previous == null) continue;
                combined = combined.withMissingFilled(regexParser.parse(previous, today));
            }
        }
        boolean needLlm = (combined.examDate() == null && !combined.examDatePast()
                    && RegexConditionParser.mentionsDate(message))
                || (combined.dailyMinutes() == null && RegexConditionParser.mentionsDaily(message));
        if (needLlm) {
            try {
                ExtractedCondition parsed = extractWithLlm(message, today);
                combined = combined.withMissingFilled(parsed);
            } catch (Exception e) {
                log.warn("조건 추출 LLM 실패, 정규식·이전 질문 결과를 유지합니다: {}", e.getMessage());
            }
        }
        return combined;
    }

    /** 지난 날짜는 이미 인식한 것으로 간주하고 되묻기 단계로 넘긴다. */
    private static boolean isComplete(ExtractedCondition c) {
        return c != null && (c.examDate() != null || c.examDatePast()) && c.dailyMinutes() != null;
    }

    private ExtractedCondition extractWithLlm(String message, LocalDate today) throws IOException {
        Map<String, Object> schema = Map.of(
                "type", "object",
                "properties", Map.of(
                        "majorType", Map.of("type", "string", "enum", List.of("MAJOR", "RELATED", "NON_MAJOR", "UNKNOWN")),
                        "examType", Map.of("type", "string", "enum", List.of("WRITTEN", "PRACTICAL", "UNKNOWN")),
                        "examDate", Map.of("type", "string"),
                        "dailyHours", Map.of("type", "number")),
                "required", List.of("majorType", "examType", "examDate", "dailyHours"));
        String raw = ollama.chat(systemPromptTemplate.replace("{{today}}", today.toString()), message, schema, 0);
        JsonNode node = objectMapper.readTree(raw);
        MajorType major = null;
        ExamType examType = null;
        LocalDate date = null;
        Integer daily = null;
        if (RegexConditionParser.mentionsMajor(message))
            major = MajorType.fromCode(node.path("majorType").asText());
        if (RegexConditionParser.mentionsExamType(message))
            examType = ExamType.fromCode(node.path("examType").asText());
        if (RegexConditionParser.mentionsDate(message)) {
            String rawDate = node.path("examDate").asText("");
            try {
                LocalDate parsed = LocalDate.parse(rawDate);
                if (!parsed.isBefore(today) && !parsed.isAfter(today.plusYears(2))) date = parsed;
            } catch (java.time.format.DateTimeParseException ignored) {
                // LLM 날짜 형식이 잘못됐으면 수용하지 않는다.
            }
        }
        if (RegexConditionParser.mentionsDaily(message)) {
            double hours = node.path("dailyHours").asDouble(0);
            if (Double.isFinite(hours) && hours >= 0.5 && hours <= 16) {
                daily = (int) Math.round(hours * 60);
            }
        }
        return new ExtractedCondition(major, examType, date, false, daily);
    }
}
