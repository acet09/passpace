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
    private static final Pattern TOTAL = Pattern.compile("(?:총|전체|누적|순공(?:부)?)\\s*(?:공부\\s*시간|학습\\s*시간|시간)?\\s*[:은는]?\\s*(?:약|대략)?\\s*(\\d{1,4}(?:\\.\\d)?)\\s*시간");
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
            {"데이터베이스(?:\\s*구축)?|DB\\s*구축", "데이터베이스 구축"},
            {"프로그래밍\\s*언어(?:\\s*활용)?", "프로그래밍 언어 활용"},
            {"정보\\s*시스템(?:\\s*구축\\s*관리)?", "정보시스템 구축관리"},
            {"정보처리\\s*실무", "정보처리 실무"},
            {"데이터\\s*모델링", "데이터 모델링의 이해"},
            {"SQL\\s*(?:기본|활용)", "SQL 기본 및 활용"},
    };
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

    /** SQLD 처럼 필기·실기 구분이 없는 시험은 WRITTEN 으로 고정한 사본 */
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
        return null;
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

    BigDecimal totalHours(String s) {
        Matcher m = TOTAL.matcher(s);
        return m.find() ? new BigDecimal(m.group(1)).setScale(2, RoundingMode.HALF_UP) : null;
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
