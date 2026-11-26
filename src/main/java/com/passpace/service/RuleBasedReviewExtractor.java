package com.passpace.service;

import com.passpace.constant.ExamType;
import com.passpace.constant.MajorType;
import com.passpace.constant.StudyMethod;
import com.passpace.domain.ExtractedReview;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [용성] 규칙(정규식) 기반 후기 추출기 - 공통 계약 ReviewExtractor 의 1차 구현.
 *
 * 원칙
 *  - 원문에 없으면 null (추측 금지)
 *  - "한 달 준비" → 준비기간 30일. 총 공부시간으로 바꾸지 않는다 (기획안 7.1.3)
 *  - 규칙으로 못 잡는 표현이 많으면 나중에 LLM 추출기로 교체 (같은 인터페이스)
 *  - 근거(evidenceText)는 원문 문장이 아니라 ReviewSummary 요약문 (원문 저장 금지)
 */
@Component
public class RuleBasedReviewExtractor implements ReviewExtractor {

    // 준비 기간
    private static final Pattern MONTHS = Pattern.compile("(?<![\\d.])(\\d{1,2})\\s*(?:개월|달)(?!\\s*(?:뒤|후|전|지나|만에\\s*결과))");   // "2달 뒤 결과 발표"는 준비 기간 아님
    private static final Pattern WEEKS = Pattern.compile("(?<![\\d.])(\\d{1,2})\\s*주\\s*(?:일)?\\s*(?:동안|간|만에|정도|준비|공부|컷|벼락|독학|단기|쯤|넘게|이상|가량|내외)");
    private static final Pattern DAYS = Pattern.compile("(?<![\\d.])(\\d{1,3})\\s*일\\s*(?:동안|간|만에|정도|준비|공부|컷|벼락|독학|단기|쯤|넘게|이상|가량|내외)");
    // "벼락치기 2일", "준비 기간: 10일", "공부 기간 3주"
    private static final Pattern DAYS_AFTER = Pattern.compile("(?:벼락치기|준비\\s*기간|공부\\s*기간|기간)\\s*[:은는]?\\s*(?:약|대략)?\\s*(\\d{1,3})\\s*(일|주)");
    // "하루 컷", "하루 벼락치기", "하루만에"
    private static final Pattern ONE_DAY = Pattern.compile("하루\\s*(?:컷|벼락치기|만에)");
    // [4차 수정] 한글 수 표현. "한 달 뒤 발표", "일주일에 3번", "한 달 남았" 같은 말은 준비 기간이 아니므로 제외
    private static final String KO_NUM = "(열한|열두|다섯|여섯|일곱|여덟|아홉|한|두|세|석|네|넉|열)";
    private static final String NOT_PERIOD = "(?!\\s*(?:뒤|후|전|지나|마다|에\\s*한|에\\s*\\d|에\\s*(?:한|두|세)\\s*번|남았|남은|만에\\s*결과|간격))";
    private static final Pattern KO_MONTHS = Pattern.compile("(?<![가-힣])" + KO_NUM + "\\s*(?:달|개월)" + NOT_PERIOD);
    private static final Pattern KO_WEEKS = Pattern.compile("(?<![가-힣])" + KO_NUM + "\\s*주\\s*(?:일)?\\s*(?:동안|간|만에|정도|준비|공부|컷|벼락|독학|단기|쯤|넘게|이상|가량|내외)");
    private static final Pattern ONE_WEEK = Pattern.compile("(?<![가-힣])일\\s*주일" + NOT_PERIOD);
    private static final Pattern KO_DAYS = Pattern.compile("(?<![가-힣])(이틀|사흘|나흘|닷새|열흘|보름)" + NOT_PERIOD);
    private static final Pattern HALF_YEAR = Pattern.compile("(?<![가-힣])반\\s*년" + NOT_PERIOD);
    // "하루 세 시간", "매일 두시간 반"
    private static final Pattern KO_DAILY_HOUR = Pattern.compile("(?:하루|매일|일\\s*평균|평일)\\s*(?:에|평균|에\\s*평균)?\\s*(?:약|대략|최소)?\\s*"
            + KO_NUM + "\\s*시간(\\s*반)?");

    // [6차 보강] 하루 공부시간 표현 확장 (후기에 흔한데 놓치던 것)
    //  - 범위: "하루 3~4시간", "매일 2-3시간" → 평균
    //  - 사이에 말이 낀 경우: "하루에 꾸준히 2시간", "매일 퇴근 후 3시간" (마침표·숫자 없이 15자 이내)
    //  - 앞말: "퇴근 후 2시간씩", "평일 저녁 3시간", "일과 후 2시간"
    //  - 평일·주말 분리: "평일 2시간 주말 6시간" → (평일×5 + 주말×2) ÷ 7
    //  - 주 단위: "일주일에 10시간", "주 15시간" → ÷ 7 (글에 적힌 숫자를 하루 평균으로 바꾼 것, 추측 아님)
    //  오인식 방지: "하루 만에 2시간짜리 강의", "시험 시간 2시간", "2시간 걸려" 등은 제외
    private static final String NUM = "(\\d{1,2}(?:\\.\\d)?)";
    private static final String RANGE = NUM + "(?:\\s*(?:~|-|∼|〜|에서)\\s*" + NUM + ")?\\s*시간(\\s*반|\\s*(\\d{1,2})\\s*분)?";
    private static final String NOT_STUDY = "(?!\\s*(?:짜리|분량|걸|정도\\s*걸|동안\\s*(?:시험|진행)|시험|강의|영상|소요))";
    private static final Pattern DAILY_RANGE = Pattern.compile(
            "(?:하루|매일|일\\s*평균|평일|퇴근\\s*(?:후|하고)|일과\\s*(?:후|끝나고)|저녁마다|매일\\s*저녁)"
                    + "(?![^\\d.!?\\n]{0,15}?만에)[^\\d.!?\\n]{0,15}?" + RANGE + NOT_STUDY);
    private static final Pattern WEEKDAY_WEEKEND = Pattern.compile(
            "평일[^\\d.!?\\n]{0,10}?" + NUM + "(?:\\s*(?:~|-|∼)\\s*" + NUM + ")?\\s*시간[^.!?\\n]{0,20}?주말[^\\d.!?\\n]{0,10}?"
                    + NUM + "(?:\\s*(?:~|-|∼)\\s*" + NUM + ")?\\s*시간");
    private static final Pattern WEEKLY = Pattern.compile(
            "(?<![\\d가-힣])(?:일주일|1주일|한\\s*주|주)\\s*(?:에|당|동안|마다)?\\s*(?:약|평균|대략|최소)?\\s*" + RANGE + NOT_STUDY);

    // 하루 공부시간: "하루 3시간", "하루에 2.5시간", "하루 평균 2시간 30분", "하루 90분"
    private static final Pattern DAILY_HOUR = Pattern.compile("(?:하루|매일|일\\s*평균|평일)\\s*(?:에|평균|에\\s*평균)?\\s*(?:약|대략|최소)?\\s*(\\d{1,2}(?:\\.\\d)?)\\s*시간(?:\\s*(\\d{1,2})\\s*분)?" + NOT_STUDY);
    private static final Pattern DAILY_MIN = Pattern.compile("(?:하루|매일|일\\s*평균|평일)\\s*(?:에|평균)?\\s*(?:약|대략|최소)?\\s*(\\d{2,3})\\s*분");
    // 총 공부시간
    private static final Pattern TOTAL = Pattern.compile("(?:총|전체|누적|순공(?:부)?)\\s*(?:공부\\s*시간|학습\\s*시간|시간)?\\s*[:은는]?\\s*(?:약|대략)?\\s*(\\d{1,4}(?:\\.\\d)?)\\s*시간(?:\\s*(\\d{1,2})\\s*분)?");
    /**
     * [11-19] 표·일지형 후기의 총 시간: "| **합계** | **23h 56m** |", "공부 시간 60시간 15분".
     * "하루 공부시간 3시간", "평일엔 공부 시간 2시간씩"처럼 하루 단위 시간은 제외한다.
     */
    private static final Pattern TOTAL_LOG = Pattern.compile(
            "(?:합계|(?<!(?:하루|매일|평균|평일|주말|일일|주당)(?:에|엔|에는)?\\s{0,2})공부\\s*시간)[\\s|*:은는]{0,12}(?:약|대략)?\\s*"
                    + "(\\d{1,4}(?:\\.\\d)?)\\s*(?:시간|[hH](?![A-Za-z]))(?:\\s*(\\d{1,2})\\s*(?:분|[mM](?![A-Za-z])))?(?!\\s*(?:씩|정도\\s*씩))");
    // [11-23] "시간 정보 없음"으로 빠진 후기 표본(티스토리·velog 18건)에서 찾은 표현. 기존 규칙이 값을 못 찾았을 때만 쓴다
    //  - 준비 기간: "약 3주의 기간", "기간은 1-2주로", "시험 7일 전부터 준비", "공부할 수 있는 날은 7일",
    //              "4월 26일 ~ 5월 17일 공부", "시험 하루 전에 공부"·"전날 벼락치기"(= 1일)
    //  - 총 공부시간: "1일 (10시간) 벼락치기", "10시간 벼락치기", "전날 14시간 정도 공부"
    private static final Pattern PERIOD_OF = Pattern.compile("(?<![\\d.])(\\d{1,3})\\s*(일|주)\\s*(?:가량|정도)?\\s*의\\s*(?:준비\\s*|공부\\s*)?기간");
    private static final Pattern PERIOD_RANGE = Pattern.compile(
            "(?:(?<!(?:접수|원서|발표|시험)\\s?)기간|준비(?!물)|공부)[^.!?\\n\\d]{0,10}?(\\d{1,2})\\s*(?:~|-|∼|〜)\\s*(\\d{1,2})\\s*(일|주|개월|달)");
    private static final Pattern DAYS_BEFORE_START = Pattern.compile(
            "(?<![\\d.])(\\d{1,3})\\s*(일|주)\\s*전부터[^.!?\\n]{0,10}?(?:준비|공부)");
    private static final Pattern AVAILABLE_DAYS = Pattern.compile(
            "공부\\s*할\\s*수\\s*있는\\s*(?:날|기간)\\s*[은는이]?\\s*(?:약|총)?\\s*(\\d{1,3})\\s*일");
    private static final Pattern DATE_SPAN = Pattern.compile(
            "(\\d{1,2})\\s*월\\s*(\\d{1,2})\\s*일\\s*(부터)?\\s*([^.!?\\n]{0,30}?)(\\d{1,2})\\s*월\\s*(\\d{1,2})\\s*일\\s*(까지)?([^.!?\\n]{0,20})");
    private static final Pattern STUDY_WORD = Pattern.compile("공부|준비(?!물)|학습");
    /** 날짜 범위가 시험 일정(접수·발표 등)이면 준비 기간이 아니다 */
    private static final Pattern SCHEDULE_WORD = Pattern.compile("접수|원서|발표|시행|응시료|일정|공고");
    private static final Pattern EVE_STUDY = Pattern.compile(
            "(?:하루\\s*전(?:날)?에?|전날(?:에)?)[^.!?\\n]{0,20}?(?:공부|벼락|훑|준비(?!물))");
    private static final Pattern DAY_PAREN_HOURS = Pattern.compile("(?<![\\d.])(\\d{1,2})\\s*일\\s*\\(\\s*(\\d{1,3})\\s*시간\\s*\\)");
    private static final Pattern CRAM_HOURS = Pattern.compile(
            "(?<![\\d.])(\\d{1,3})\\s*시간\\s*(?:만에\\s*)?벼락\\s*치기(?!\\s*(?:특강|강의|영상|요약))");
    private static final Pattern EVE_HOURS = Pattern.compile(
            "(?:전날|하루\\s*전)[^.!?\\n\\d]{0,25}?(\\d{1,2})\\s*시간\\s*(?:정도|가량|쯤|넘게)?\\s*(?:공부|벼락)");

    // 응시 연도·회차: "2025년 2회", "2025 1회차"
    private static final Pattern ROUND = Pattern.compile("(20\\d{2})\\s*년?\\s*(?:정기\\s*)?(?:기사\\s*)?(\\d)\\s*회");
    private static final Pattern PROOF = Pattern.compile("최종\\s*합격|합격\\s*(?:증|화면|인증|확인|발표)|\\d{2,3}\\s*점");

    /**
     * 과목 별칭 → DB 과목명(CERTIFICATION_SUBJECTS.subject_name, 2027~ 출제기준 + SQLD).
     * 2026년 이전 후기의 "소프트웨어 설계"는 2027년 기준에 없는 과목이라 이름 그대로 남긴다.
     */
    private static final String[][] SUBJECTS = {
            {"소프트웨어\\s*설계", "소프트웨어 설계"},
            {"소프트웨어\\s*개발", "소프트웨어 개발"},
            {"데이터베이스(?!\\s*(?:일반|실무))(?:\\s*구축)?|DB\\s*구축", "데이터베이스 구축"},
            {"프로그래밍\\s*언어(?:\\s*활용)?", "프로그래밍 언어 활용"},
            {"정보\\s*시스템(?:\\s*구축\\s*관리)?", "정보시스템 구축관리"},
            {"정보처리\\s*실무", "정보처리 실무"},
            {"데이터\\s*모델링", "데이터 모델링의 이해"},
            {"SQL\\s*(?:기본|활용)", "SQL 기본 및 활용"},
            // [11-14] 컴활 1급 (필기 3과목 / 실기 2과목)
            {"컴퓨터\\s*일반", "컴퓨터 일반"},
            {"스프레드\\s*시트\\s*일반", "스프레드시트 일반"},
            {"데이터베이스\\s*일반", "데이터베이스 일반"},
            {"스프레드\\s*시트\\s*실무|엑셀\\s*실기", "스프레드시트 실무"},
            {"데이터베이스\\s*실무|액세스\\s*실기", "데이터베이스 실무"},
            // [11-14] ADsP (필기 3과목)
            {"데이터\\s*이해", "데이터 이해"},
            {"데이터\\s*분석\\s*기획", "데이터분석 기획"},
            {"데이터\\s*분석(?!\\s*(?:기획|준\\s*전문가|전문가|가))", "데이터분석"},
    };
    /** [11-16] 과목별 시간 추출기(SubjectStudyExtractor)가 같은 사전을 쓰도록 공개. 사본을 돌려준다 */
    static String[][] subjectAliases() {
        return java.util.Arrays.stream(SUBJECTS).map(String[]::clone).toArray(String[][]::new);
    }

    private static final Pattern[] SUBJECT_PATTERNS = java.util.Arrays.stream(SUBJECTS)
            .map(a -> Pattern.compile(a[0])).toArray(Pattern[]::new);

    @Override
    public ExtractedReview extract(String title, String text) {
        String all = ((title == null ? "" : title) + " \n " + (text == null ? "" : text));

        Integer dailyMinutes = dailyMinutes(all);
        ExtractedReview r = new ExtractedReview(
                passed(all),
                examType(title == null ? "" : title, all),
                roundYear(all),
                roundNo(all),
                major(all),
                prepDays(all),
                dailyMinutes,
                totalHours(all),
                subjects(all),
                method(all),
                PROOF.matcher(all).find(),
                null);
        // 근거: 원문 문장을 옮기지 않고 구조화 값으로 만든 요약문 (기획안 7.1.4, 사용자 결정)
        return withEvidence(r, ReviewSummary.of(r));
    }

    /** record 는 불변이라 근거 문장만 바꾼 사본을 만든다 */
    public static ExtractedReview withEvidence(ExtractedReview r, String evidence) {
        return new ExtractedReview(r.passed(), r.examType(), r.examYear(), r.roundNo(), r.majorType(),
                r.prepDays(), r.dailyMinutes(), r.totalHours(), r.studySubjects(), r.studyMethod(), r.proof(), evidence);
    }

    /** SQLD·ADsP 처럼 필기·실기 구분이 없는 시험은 WRITTEN 으로 고정한 사본 */
    public static ExtractedReview withExamType(ExtractedReview r, ExamType examType) {
        ExtractedReview c = new ExtractedReview(r.passed(), examType, r.examYear(), r.roundNo(), r.majorType(),
                r.prepDays(), r.dailyMinutes(), r.totalHours(), r.studySubjects(), r.studyMethod(), r.proof(), null);
        return withEvidence(c, ReviewSummary.of(c));
    }

    // ---------------- 항목별 규칙 ----------------

    /** "불합격·떨어"를 먼저 본다 ("불합격"에도 "합격"이 들어 있으므로) */
    Boolean passed(String s) {
        if (s.contains("불합격") || s.contains("떨어졌") || s.contains("떨어진") || s.contains("과락으로")) return false;
        if (s.contains("합격")) return true;
        return null;
    }

    /**
     * 시험 구분: 제목을 먼저 보고, 제목에 둘 다 있거나 없으면 본문 언급 횟수로 판단
     * (본문에서 한쪽이 다른 쪽의 2배 이상 언급될 때만. 아니면 null → 사람이 확인)
     */
    ExamType examType(String title, String all) {
        ExamType byTitle = examTypeOnce(title);
        if (byTitle != null) return byTitle;
        if (title.contains("필기") && title.contains("실기")) return null;     // "필기·실기 합격" → 판단 보류
        int w = count(all, "필기"), p = count(all, "실기");
        if (w > 0 && w >= p * 2) return ExamType.WRITTEN;
        if (p > 0 && p >= w * 2) return ExamType.PRACTICAL;
        return null;
    }

    ExamType examType(String s) {
        return examType("", s);
    }

    private static ExamType examTypeOnce(String s) {
        boolean written = s.contains("필기");
        boolean practical = s.contains("실기");
        if (written && !practical) return ExamType.WRITTEN;
        if (practical && !written) return ExamType.PRACTICAL;
        return null;
    }

    MajorType major(String s) {
        if (s.contains("비전공")) return MajorType.NON_MAJOR;
        if (s.matches("(?s).*(유사\\s*전공|관련\\s*전공|정보통신과|전자공학).*")) return MajorType.RELATED;
        if (s.matches("(?s).*(전공자|컴공|컴퓨터공학|소프트웨어학과|컴퓨터과학).*")) return MajorType.MAJOR;
        return null;
    }

    Integer prepDays(String s) {
        Matcher m = MONTHS.matcher(s);
        if (m.find()) return Integer.parseInt(m.group(1)) * 30;
        m = WEEKS.matcher(s);
        if (m.find()) return Integer.parseInt(m.group(1)) * 7;
        m = DAYS.matcher(s);
        if (m.find()) return Integer.parseInt(m.group(1));
        m = DAYS_AFTER.matcher(s);
        if (m.find()) return Integer.parseInt(m.group(1)) * ("주".equals(m.group(2)) ? 7 : 1);
        if (ONE_DAY.matcher(s).find()) return 1;
        m = KO_MONTHS.matcher(s);
        if (m.find()) return koNumber(m.group(1)) * 30;
        m = KO_WEEKS.matcher(s);
        if (m.find()) return koNumber(m.group(1)) * 7;
        if (ONE_WEEK.matcher(s).find()) return 7;
        m = KO_DAYS.matcher(s);
        if (m.find()) return switch (m.group(1)) {
            case "이틀" -> 2;
            case "사흘" -> 3;
            case "나흘" -> 4;
            case "닷새" -> 5;
            case "열흘" -> 10;
            default -> 15;          // 보름
        };
        if (HALF_YEAR.matcher(s).find()) return 180;
        return morePrepDays(s);
    }

    /** [11-23] 기존 규칙이 못 찾은 준비 기간 표현 (표본 분석 결과). 못 찾으면 null */
    static Integer morePrepDays(String s) {
        Matcher m = PERIOD_OF.matcher(s);
        if (m.find()) return Integer.parseInt(m.group(1)) * ("주".equals(m.group(2)) ? 7 : 1);
        m = PERIOD_RANGE.matcher(s);
        if (m.find()) {
            double avg = (Integer.parseInt(m.group(1)) + Integer.parseInt(m.group(2))) / 2.0;
            int unit = switch (m.group(3)) {
                case "주" -> 7;
                case "개월", "달" -> 30;
                default -> 1;
            };
            return (int) Math.round(avg * unit);
        }
        m = DAYS_BEFORE_START.matcher(s);
        if (m.find()) return Integer.parseInt(m.group(1)) * ("주".equals(m.group(2)) ? 7 : 1);
        m = AVAILABLE_DAYS.matcher(s);
        if (m.find()) return Integer.parseInt(m.group(1));
        m = DATE_SPAN.matcher(s);
        while (m.find()) {
            Integer d = dateSpanDays(m);
            if (d != null) return d;
        }
        m = DAY_PAREN_HOURS.matcher(s);
        if (m.find()) return Integer.parseInt(m.group(1));
        if (EVE_STUDY.matcher(s).find()) return 1;
        return null;
    }

    /**
     * "4월 26일 ~ 5월 17일", "4월 26일부터 5월 17일까지 공부" → 날짜 차이(일).
     * 두 날짜 사이가 물결·대시이거나 "부터 … 까지"로 이어지고, 같은 문장에 공부·준비·기간이 있을 때만.
     */
    private static Integer dateSpanDays(Matcher m) {
        String between = m.group(4) == null ? "" : m.group(4);
        boolean tilde = between.strip().matches("[~∼〜\\-–]?") || between.contains("~") || between.contains("∼");
        boolean fromTo = m.group(3) != null && m.group(7) != null;
        if (!tilde && !fromTo) return null;
        if (!STUDY_WORD.matcher(m.group(0)).find() || SCHEDULE_WORD.matcher(m.group(0)).find()) return null;
        try {
            java.time.LocalDate a = java.time.LocalDate.of(2001, Integer.parseInt(m.group(1)), Integer.parseInt(m.group(2)));
            java.time.LocalDate b = java.time.LocalDate.of(2001, Integer.parseInt(m.group(5)), Integer.parseInt(m.group(6)));
            if (b.isBefore(a)) b = b.plusYears(1);
            long days = java.time.temporal.ChronoUnit.DAYS.between(a, b);
            return days >= 1 && days <= 365 ? (int) days : null;
        } catch (java.time.DateTimeException e) {
            return null;
        }
    }

    Integer dailyMinutes(String s) {
        Matcher m = WEEKDAY_WEEKEND.matcher(s);
        if (m.find()) {
            double weekday = avg(m.group(1), m.group(2)), weekend = avg(m.group(3), m.group(4));
            return (int) Math.round((weekday * 5 + weekend * 2) / 7 * 60);
        }
        m = DAILY_HOUR.matcher(s);
        if (m.find()) {
            double hours = Double.parseDouble(m.group(1));
            int extra = m.group(2) == null ? 0 : Integer.parseInt(m.group(2));
            return (int) Math.round(hours * 60) + extra;
        }
        m = DAILY_MIN.matcher(s);
        if (m.find()) return Integer.parseInt(m.group(1));
        m = KO_DAILY_HOUR.matcher(s);
        if (m.find()) return koNumber(m.group(1)) * 60 + (m.group(2) == null ? 0 : 30);
        m = DAILY_RANGE.matcher(s);
        if (m.find()) return rangeMinutes(m);
        m = WEEKLY.matcher(s);
        if (m.find()) return (int) Math.round(rangeMinutes(m) / 7.0);
        return null;
    }

    /** RANGE 그룹(시작·끝·반·분) → 분. 범위면 평균 */
    private static int rangeMinutes(Matcher m) {
        double h = avg(m.group(1), m.group(2));
        int extra = m.group(3) == null ? 0 : (m.group(4) != null ? Integer.parseInt(m.group(4)) : 30);
        return (int) Math.round(h * 60) + extra;
    }

    private static double avg(String a, String b) {
        double x = Double.parseDouble(a);
        return b == null ? x : (x + Double.parseDouble(b)) / 2;
    }

    /** 한·두·세(석)·네(넉)·다섯 … 열두 → 숫자 */
    static int koNumber(String w) {
        return switch (w) {
            case "한" -> 1;
            case "두" -> 2;
            case "세", "석" -> 3;
            case "네", "넉" -> 4;
            case "다섯" -> 5;
            case "여섯" -> 6;
            case "일곱" -> 7;
            case "여덟" -> 8;
            case "아홉" -> 9;
            case "열" -> 10;
            case "열한" -> 11;
            default -> 12;          // 열두
        };
    }

    /** [11-19] "N시간 M분"·"Nh Mm"의 분까지 반영하고, 일반 문장 다음에 표·일지형 합계를 본다 */
    BigDecimal totalHours(String s) {
        for (Pattern p : new Pattern[]{TOTAL, TOTAL_LOG}) {
            Matcher m = p.matcher(s);
            if (m.find()) {
                BigDecimal h = new BigDecimal(m.group(1));
                if (m.group(2) != null) {
                    h = h.add(new BigDecimal(m.group(2)).divide(BigDecimal.valueOf(60), 4, RoundingMode.HALF_UP));
                }
                return h.setScale(2, RoundingMode.HALF_UP);
            }
        }
        // [11-23] 벼락치기형: "1일 (10시간)", "10시간 벼락치기", "전날 14시간 정도 공부" → 그 시간이 곧 총 공부시간
        for (Pattern p : new Pattern[]{DAY_PAREN_HOURS, CRAM_HOURS, EVE_HOURS}) {
            Matcher m = p.matcher(s);
            if (m.find()) {
                String hours = p == DAY_PAREN_HOURS ? m.group(2) : m.group(1);
                return new BigDecimal(hours).setScale(2, RoundingMode.HALF_UP);
            }
        }
        return null;
    }

    Integer roundYear(String s) {
        Matcher m = ROUND.matcher(s);
        return m.find() ? Integer.parseInt(m.group(1)) : null;
    }

    Integer roundNo(String s) {
        Matcher m = ROUND.matcher(s);
        return m.find() ? Integer.parseInt(m.group(2)) : null;
    }

    String subjects(String s) {
        List<String> found = new ArrayList<>();
        for (int i = 0; i < SUBJECTS.length; i++) {
            if (SUBJECT_PATTERNS[i].matcher(s).find() && !found.contains(SUBJECTS[i][1])) found.add(SUBJECTS[i][1]);
        }
        return found.isEmpty() ? null : String.join(",", found);
    }

    /** "기출" 언급과 "이론·개념" 언급 횟수로 학습 방식 판단 */
    StudyMethod method(String s) {
        int pastExam = count(s, "기출");
        int theory = count(s, "이론") + count(s, "개념");
        if (pastExam == 0 && theory == 0) return null;
        if (pastExam >= theory * 2) return StudyMethod.PAST_EXAM;
        if (theory >= pastExam * 2) return StudyMethod.THEORY;
        return StudyMethod.BALANCED;
    }

    private static int count(String s, String word) {
        int n = 0;
        for (int i = s.indexOf(word); i >= 0; i = s.indexOf(word, i + word.length())) n++;
        return n;
    }
}
