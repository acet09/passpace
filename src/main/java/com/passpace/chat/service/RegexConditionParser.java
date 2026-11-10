package com.passpace.chat.service;

import com.passpace.chat.dto.ChatDtos.ExtractedCondition;
import com.passpace.common.code.ExamType;
import com.passpace.common.code.MajorType;

import java.time.DateTimeException;
import java.time.LocalDate;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [동건] 질문에서 조건을 정규식으로 뽑는다 (Spring 없이 테스트 가능한 순수 클래스).
 * 잡지 못한 값은 null → ConditionExtractor 가 앞 질문·LLM 으로 한 번 더 채운다.
 *
 * 예) "비전공자가 정보처리기사 필기 준비중이다. 시험날은 3월 20일, 하루 2.5시간"
 *     → NON_MAJOR, WRITTEN, (다가오는) 3월 20일, 150분
 */
public class RegexConditionParser {

    // ---------------- 날짜 ----------------
    private static final Pattern FULL_DATE = Pattern.compile("(20\\d{2})\\s*[년./-]\\s*(\\d{1,2})\\s*[월./-]\\s*(\\d{1,2})");
    private static final Pattern MONTH_DAY = Pattern.compile("(\\d{1,2})\\s*월\\s*(\\d{1,2})\\s*일");
    private static final Pattern SLASH_DATE = Pattern.compile("(?<![\\d./])(\\d{1,2})/(\\d{1,2})(?![\\d/])");
    /** "시험 3.20" 처럼 시험 관련 단어 바로 뒤의 점 날짜만 인정 ("하루 2.5시간" 과 헷갈리지 않게) */
    private static final Pattern DOT_DATE = Pattern.compile(
            "(?:시험|시험일|시험날|필기|실기|일정)\\s*(?:은|는|이|일|날|일은|날은)?\\s*(\\d{1,2})\\.(\\d{1,2})(?![\\d.]|\\s*(?:시간|분|배|%|점|회))");

    // ---------------- 하루 공부시간 ----------------
    /** "하루", "매일", "평일" 뒤에 오는 시간만 하루 공부시간으로 본다 */
    private static final String DAY = "(?:하루|매일|평일)\\s*(?:에는|에|은|는|평균|에 평균)?\\s*(?:최대\\s*|약\\s*|대략\\s*)?";
    private static final Pattern DAILY_RANGE = Pattern.compile(DAY + "(\\d{1,2}(?:\\.\\d+)?)\\s*(?:~|-|에서)\\s*(\\d{1,2}(?:\\.\\d+)?)\\s*시간");
    private static final Pattern DAILY_HALF = Pattern.compile(DAY + "(\\d{1,2})\\s*시간\\s*반");
    private static final Pattern DAILY_HOUR = Pattern.compile(DAY + "(\\d{1,2}(?:\\.\\d+)?)\\s*시간(?:\\s*(\\d{1,2})\\s*분)?");
    private static final Pattern DAILY_MIN = Pattern.compile(DAY + "(\\d{2,3})\\s*분");
    private static final Pattern DAILY_KOR = Pattern.compile(DAY + "(한|두|세|네|다섯|여섯|일곱|여덟|아홉|열)\\s*시간(\\s*반)?");
    private static final Pattern PER_DAY = Pattern.compile("(\\d{1,2}(?:\\.\\d+)?)\\s*시간\\s*씩");
    /** "주 10시간" → 하루 평균으로 나눈다 (하루 값이 따로 없을 때만) */
    private static final Pattern WEEKLY = Pattern.compile("(?:일주일|주)\\s*(?:에|에는)?\\s*(\\d{1,2})\\s*시간");
    private static final Map<String, Integer> KOR_NUM = Map.of("한", 1, "두", 2, "세", 3, "네", 4, "다섯", 5,
            "여섯", 6, "일곱", 7, "여덟", 8, "아홉", 9, "열", 10);

    // ---------------- 전공·시험 구분 ----------------
    private static final Pattern NOT_NON_MAJOR = Pattern.compile("비전공(?:자)?\\s*(?:은|는|이|가)?\\s*(?:아니|아님|아닌)");
    private static final Pattern WRITTEN_DONE = Pattern.compile("필기\\s*(?:는|은|를|을|도)?\\s*(?:붙|합격|통과|끝|면제|됐|했)");

    // ---------------- 질문 종류 ----------------
    /** 학습 계획 질문으로 볼 단어 */
    private static final Pattern PLAN_WORDS = Pattern.compile("계획|플랜|일정|스케줄|공부|학습|준비|남았|남은|디데이|D-|d-|며칠|몇\\s*주|어떻게");

    /** 하루 공부시간 허용 범위 0.5~16시간 */
    static final int MIN_DAILY = 30;
    static final int MAX_DAILY = 16 * 60;

    public ExtractedCondition parse(String message, LocalDate today) {
        String s = message == null ? "" : message;
        DateResult d = examDate(s, today);
        return new ExtractedCondition(major(s), examType(s), d == null ? null : d.date(),
                d != null && d.past(), dailyMinutes(s));
    }

    /** 단순 인사·과목 질의는 계획 요청으로 간주하지 않는다. */
    public boolean isPlanQuestion(String s, ExtractedCondition c) {
        if (s == null || s.isBlank()) return false;
        if (s.contains("과목") && (s.contains("뭐") || s.contains("어떤") || s.contains("있어")
                || s.contains("목록") || s.contains("알려"))) return false;
        if (PLAN_WORDS.matcher(s).find()) return true;
        // '정처기 필기 따고 싶어'도 학습 의도로 인식한다.
        if ((s.contains("정보처리기사") || s.contains("정처기") || s.toUpperCase(java.util.Locale.ROOT).contains("SQLD"))
                && (s.contains("하고싶") || s.contains("하고 싶") || s.contains("따려")
                || s.contains("따고") || s.contains("취득") || s.contains("목표"))) return true;
        if (c != null && c.examDate() != null && c.dailyMinutes() != null
                && (s.contains("시험") || s.contains("필기") || s.contains("실기"))) return true;
        // 계획 질문 후 "하루 3시간이면?" 같은 조건 변경 질문
        return c != null && (c.dailyMinutes() != null || c.examDate() != null)
                && (s.contains("이면") || s.contains("라면") || s.contains("그럼") || s.contains("바꾸") || s.contains("늘리") || s.contains("줄이"));
    }

    // LLM 값은 이번 질문에 실제 단서가 있을 때만 허용한다.
    static boolean mentionsMajor(String s) {
        return s != null && (s.contains("전공") || s.contains("컴공") || s.contains("관련학과") || s.contains("비관련"));
    }

    static boolean mentionsExamType(String s) {
        return s != null && (s.contains("필기") || s.contains("실기") || s.contains("작업형") || s.contains("필답"));
    }

    static boolean mentionsDate(String s) {
        return s != null && (s.contains("시험") || s.contains("날짜") || s.contains("월") || s.contains("일") ||
                s.contains("남았") || s.contains("남은")) &&
                (s.matches("(?s).*\\d{1,4}[./년월-].*") || s.matches("(?s).*\\d+\\s*(?:일|주|개월|달)\\s*(?:남|후).*") || s.contains("다음달"));
    }

    static boolean mentionsDaily(String s) {
        // '총 150시간'은 전체 예산이지 '하루 150시간'이 아니다.
        // 시간 단서만 있는 경우 Ollama가 일일 학습시간을 지어내지 못하도록 한다.
        if (s == null) return false;
        return DAILY_RANGE.matcher(s).find() || DAILY_HALF.matcher(s).find()
                || DAILY_HOUR.matcher(s).find() || DAILY_MIN.matcher(s).find()
                || DAILY_KOR.matcher(s).find() || PER_DAY.matcher(s).find()
                || WEEKLY.matcher(s).find();
    }

    MajorType major(String s) {
        if (s == null) return null;
        if (NOT_NON_MAJOR.matcher(s).find()) return MajorType.MAJOR;
        if (s.contains("비전공") || s.contains("비관련")) return MajorType.NON_MAJOR;
        if (s.contains("유사전공") || s.contains("관련전공") || s.contains("관련학과")) return MajorType.RELATED;
        if (s.contains("전공") || s.contains("컴공")) return MajorType.MAJOR;
        return null;
    }

    ExamType examType(String s) {
        if (s == null) return null;
        if (s.contains("실기") || s.contains("실무") || s.contains("필답") || WRITTEN_DONE.matcher(s).find()) return ExamType.PRACTICAL;
        if (s.contains("필기")) return ExamType.WRITTEN;
        return null;
    }

    record DateResult(LocalDate date, boolean past) {
    }

    DateResult examDate(String s, LocalDate today) {
        if (s == null || today == null) return null;
        Matcher m = FULL_DATE.matcher(s);
        if (m.find()) {
            LocalDate date = safeDate(Integer.parseInt(m.group(1)), Integer.parseInt(m.group(2)), Integer.parseInt(m.group(3)));
            return date == null ? null : new DateResult(date, date.isBefore(today));
        }
        m = MONTH_DAY.matcher(s);
        boolean found = m.find();
        if (!found) {
            m = SLASH_DATE.matcher(s);
            found = m.find();
        }
        if (!found) {
            m = DOT_DATE.matcher(s);
            found = m.find();
        }
        if (found) {
            int month = Integer.parseInt(m.group(1));
            int day = Integer.parseInt(m.group(2));
            LocalDate date = safeDate(today.getYear(), month, day);
            if (date == null) return null;
            if (date.isBefore(today)) date = safeDate(today.getYear() + 1, month, day);
            return date == null ? null : new DateResult(date, false);
        }
        // 명시적 상대 날짜 ("시험까지 30일 남았다" 등)
        if (s.contains("시험") || s.contains("남았") || s.contains("남은")) {
            m = Pattern.compile("(\\d{1,3})\\s*(일|주|개월|달)\\s*(?:후|남)").matcher(s);
            if (m.find()) {
                int count = Integer.parseInt(m.group(1));
                LocalDate date = switch (m.group(2)) {
                    case "주" -> today.plusWeeks(count);
                    case "개월", "달" -> today.plusMonths(count);
                    default -> today.plusDays(count);
                };
                return new DateResult(date, false);
            }
        }
        return null;
    }

    Integer dailyMinutes(String s) {
        if (s == null) return null;
        Matcher m = DAILY_RANGE.matcher(s);
        if (m.find()) return validMinutes(Math.round((Float.parseFloat(m.group(1)) + Float.parseFloat(m.group(2))) * 30));
        m = DAILY_HALF.matcher(s);
        if (m.find()) return validMinutes(Integer.parseInt(m.group(1)) * 60 + 30);
        m = DAILY_KOR.matcher(s);
        if (m.find()) return validMinutes(KOR_NUM.get(m.group(1)) * 60 + (m.group(2) != null ? 30 : 0));
        // "하루에 두 시간씩" 은 DAY 와 수사 사이의 조사도 처리한다.
        m = Pattern.compile("(?:하루|매일|평일)\\s*(?:에는|에|은|는)?\\s*(한|두|세|네|다섯|여섯|일곱|여덟|아홉|열)\\s*시간(?:\\s*반)?").matcher(s);
        if (m.find()) return validMinutes(KOR_NUM.get(m.group(1)) * 60 + (m.group().contains("반") ? 30 : 0));
        m = DAILY_HOUR.matcher(s);
        if (m.find()) return validMinutes((int) Math.round(Double.parseDouble(m.group(1)) * 60)
                + (m.group(2) == null ? 0 : Integer.parseInt(m.group(2))));
        m = DAILY_MIN.matcher(s);
        if (m.find()) return validMinutes(Integer.parseInt(m.group(1)));
        m = PER_DAY.matcher(s);
        if (m.find() && !s.matches("(?s).*\\b주\\s*\\d+.*"))
            return validMinutes((int) Math.round(Double.parseDouble(m.group(1)) * 60));
        m = WEEKLY.matcher(s);
        if (m.find()) return validMinutes((int) Math.round(Integer.parseInt(m.group(1)) * 60.0 / 7));
        // "하루 3시간이면" 과 "하루 2.5시간"을 DAY가 이미 포괄.
        return null;
    }

    private static Integer validMinutes(int minutes) {
        return minutes >= MIN_DAILY && minutes <= MAX_DAILY ? minutes : null;
    }

    private static LocalDate safeDate(int y, int m, int d) {
        try {
            return LocalDate.of(y, m, d);
        } catch (DateTimeException e) {
            return null;
        }
    }
}
