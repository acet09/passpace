package com.passpace.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [용성 · 11-16] 후기 본문에서 과목별 공부 정보를 뽑는 규칙 추출기 (1단계: 추출만).
 *
 * 아직 어디에도 연결하지 않았다 (Spring Bean 아님, DB 저장 없음).
 *  - 저장할 테이블(후기 1편 × 과목 1개 = 1줄)은 팀 합의 후 만든다
 *  - 그 전까지는 테스트와 수집 결과 확인용으로만 쓴다
 *
 * 뽑는 것 (한 문장 안에서 과목 이름 바로 뒤에 나오는 말만 본다)
 *  - HOURS     : "DB 10시간" → 10시간 / "DB는 3일" → 3일 × 하루 공부시간 (추정값 표시)
 *  - RATIO     : "DB에 40%", "DB에 절반" → 비율
 *  - SKIPPED   : "DB는 건너뜀/스킵/버림" → 0시간
 *  - DIFFICULT : "DB가 어려웠다"
 *  - EASY      : "DB는 쉬웠다", "어렵지 않았다"
 *
 * 원칙 (RuleBasedReviewExtractor 와 같음)
 *  - 원문에 없으면 뽑지 않는다 (추측 금지)
 *  - 근거는 원문 문장이 아니라 뽑은 값으로 만든 요약문
 *  - 과목 시간 합이 총 공부시간보다 크면 시간 값을 모두 버린다 (잘못 읽은 것으로 봄)
 *
 * [11-19] 학습일지(날짜로 시작하는 줄 3줄 이상)는 줄마다 적힌 과목 시간을 과목별로 더한다 ("3h 46m"·"3시간 46분"·"3:46"·"90분")
 *
 * 아직 처리하지 않는 것 (팀 결정 필요)
 *  - "3·4과목" 같은 번호 표현 (옛 5과목/새 4과목 중 어느 순서인지 알 수 없음)
 *  - 하루 공부시간이 후기에 없을 때의 기본값 → 생성자 인자로만 받는다 (null 이면 일수 → 시간 환산 안 함)
 */
public class SubjectStudyExtractor {

    public enum MentionType { HOURS, RATIO, SKIPPED, DIFFICULT, EASY }

    /**
     * 과목 1개에 대한 언급 1건.
     *
     * @param subjectName  DB 과목명 (CERTIFICATION_SUBJECTS.subject_name 표기, 옛 "소프트웨어 설계"는 그대로)
     * @param type         언급 종류
     * @param hours        과목 공부시간 (HOURS·SKIPPED 일 때만, 모르면 null)
     * @param ratioPercent 전체 중 비율 % (RATIO 일 때만)
     * @param estimated    일수 × 하루 공부시간처럼 환산한 값이면 true
     * @param evidence     요약 근거 (원문 문장 아님)
     */
    public record Mention(String subjectName, MentionType type, BigDecimal hours,
                          BigDecimal ratioPercent, boolean estimated, String evidence) { }

    /** RuleBasedReviewExtractor 사전에 없는 짧은 별칭 (후기에 자주 나옴) */
    private static final String[][] EXTRA_ALIASES = {
            {"(?<![A-Za-z])(?:DB|디비)(?![A-Za-z])", "데이터베이스 구축"},
            {"(?<![A-Za-z])SW\\s*설계", "소프트웨어 설계"},
            {"(?<![A-Za-z])SW\\s*개발", "소프트웨어 개발"},
    };

    private static final String NUM = "(\\d{1,3}(?:\\.\\d)?)";
    private static final Pattern HOURS = Pattern.compile(
            "(?<![\\d.])" + NUM + "\\s*시간(?!\\s*(?:짜리|분량|강의|영상|씩))");
    private static final Pattern DAILY_PREFIX = Pattern.compile("(?:하루|매일|하루에|평일|주말)\\s*(?:약|평균)?\\s*$");
    private static final Pattern DAYS = Pattern.compile(
            "(?<![\\d.])(\\d{1,2})\\s*일(?!\\s*(?:차|째|회|부터|까지|전|뒤|후|에\\s*\\d))");
    private static final Pattern KO_DAYS = Pattern.compile("(?<![가-힣])(이틀|사흘|나흘|닷새|일주일|열흘)");
    private static final Pattern RATIO = Pattern.compile("(?<![\\d.])(\\d{1,3})\\s*(?:%|퍼센트|프로)");
    private static final Pattern HALF = Pattern.compile("절반|반\\s*(?:정도|이상|가까이)");
    // [11-16 보정] 실제 결과 확인 후 추가한 오인식 방지 규칙
    /** 비율은 "시간을 얼마나 썼다"는 말과 함께 나올 때만 (합격 기준 "과목별 40%", "100% 맞춘다" 제외) */
    private static final Pattern RATIO_CONTEXT = Pattern.compile("시간|비중|투자|할애|배분|공부|썼|쏟");
    private static final Pattern RATIO_NOT = Pattern.compile("과락|합격|기준|맞|점|정답|득점|문항|출제|이해|미만|커트|확률");
    /** 일수는 공부했다는 말과 함께 나올 때만 ("강의 90일 들을 수 있다" 제외) */
    private static final Pattern DAYS_CONTEXT = Pattern.compile("봤|보고|공부|했|잡|투자|걸렸|만에|동안|끝냈|끝내|붙잡|팠");
    private static final Pattern DAYS_NOT = Pattern.compile("강의|수강|인강|들을\\s*수|이용\\s*기간|유효\\s*기간|남았|남은|전에|후에|뒤에");
    /** 과목 하나에 쓴 일수의 상한 (이보다 크면 전체 준비 기간을 잘못 읽은 것으로 봄) */
    private static final int MAX_SUBJECT_DAYS = 30;
    /** 시험 시간 안내는 공부 시간이 아님 ("정보처리실무, 필답형, 2시간 30분", "80문항을 2시간 안에") */
    private static final Pattern HOURS_NOT = Pattern.compile("시험|필답|문항|출제|제한|안에|이내|소요|진행|응시|시간\\s*\\d{1,2}\\s*분");
    /** 과목 이름 뒤에서 값을 찾는 거리(글자 수). 문장 끝까지 보면 다른 이야기를 잘못 붙인다 */
    private static final int WINDOW = 40;
    private static final Pattern SKIP = Pattern.compile("건너|스킵|버렸|버리고|포기|(?<![동])안\\s*(?:봤|보고|함|했)|손\\s*(?:안|도\\s*안)\\s*(?:댔|대고)");
    private static final Pattern EASY = Pattern.compile("어렵지\\s*않|쉬웠|쉬운\\s*편|쉽게|무난|금방|껌");
    private static final Pattern HARD = Pattern.compile("어려웠|어렵|헷갈|힘들|고생|취약|약점|까다");
    private static final Pattern SENTENCE = Pattern.compile("[^.!?\\n]+");

    // ---------------- [11-19] 학습일지(날짜별 기록) ----------------
    /**
     * 날짜로 시작하는 일지 줄: "| 2026-07-28 | 3h 46m | 1과목 소프트웨어 설계 |", "7/28 DB 2시간", "3일차 언어 1시간 30분", "D-10 ...".
     * 이런 줄이 MIN_LOG_LINES 줄 이상이면 학습일지로 보고, 줄마다 적힌 과목 시간을 과목별로 더한다.
     */
    private static final Pattern LOG_LINE = Pattern.compile(
            "^[\\s|*>•·-]*(?:20\\d{2}\\s*[-./년]\\s*\\d{1,2}\\s*[-./월]\\s*\\d{1,2}\\s*일?"
                    + "|\\d{1,2}\\s*월\\s*\\d{1,2}\\s*일|\\d{1,2}\\s*[./]\\s*\\d{1,2}(?![\\d.]|\\s*(?:시간|h|H))"
                    + "|\\d{1,3}\\s*일\\s*(?:차|째)|[Dd]\\s*-\\s*\\d{1,3}|[Dd]ay\\s*\\d{1,3})");
    private static final int MIN_LOG_LINES = 3;
    /** 일지 줄의 공부시간: "3h 46m", "2h", "3시간 46분", "90분", "3:46" */
    private static final Pattern LOG_HM_EN = Pattern.compile(
            "(?<![\\d.A-Za-z])(\\d{1,2}(?:\\.\\d)?)\\s*[hH](?![A-Za-z])(?:\\s*(\\d{1,2})\\s*[mM](?![A-Za-z]))?");
    private static final Pattern LOG_HM_KO = Pattern.compile("(?<![\\d.])(\\d{1,2}(?:\\.\\d)?)\\s*시간(?:\\s*(\\d{1,2})\\s*분)?");
    private static final Pattern LOG_MIN = Pattern.compile("(?<![\\d.:])(\\d{1,3})\\s*(?:분|[mM]in)(?![A-Za-z])");
    private static final Pattern LOG_COLON = Pattern.compile("(?<![\\d:])(\\d{1,2}):([0-5]\\d)(?![\\d:])");

    private final List<Pattern> patterns = new ArrayList<>();
    private final List<String> names = new ArrayList<>();
    private final Integer defaultDailyMinutes;

    /** @param defaultDailyMinutes 후기에 하루 공부시간이 없을 때 쓸 값(분). null 이면 일수를 시간으로 바꾸지 않는다 */
    public SubjectStudyExtractor(Integer defaultDailyMinutes) {
        this.defaultDailyMinutes = defaultDailyMinutes;
        for (String[] a : RuleBasedReviewExtractor.subjectAliases()) add(a[0], a[1]);
        for (String[] a : EXTRA_ALIASES) add(a[0], a[1]);
    }

    public SubjectStudyExtractor() {
        this(null);
    }

    private void add(String regex, String name) {
        patterns.add(Pattern.compile(regex));
        names.add(name);
    }

    /**
     * @param text         후기 제목 + 본문 (메모리에서만 사용)
     * @param dailyMinutes 이 후기의 하루 공부시간(분, RuleBasedReviewExtractor 결과). 모르면 null
     * @param totalHours   이 후기의 총 공부시간(시간). 모르면 null
     */
    public List<Mention> extract(String text, Integer dailyMinutes, BigDecimal totalHours) {
        if (text == null || text.isBlank()) return List.of();
        Integer perDay = dailyMinutes != null ? dailyMinutes : defaultDailyMinutes;
        Map<String, Mention> found = new LinkedHashMap<>();   // 과목+종류별 첫 언급만
        // [11-19] 학습일지 합산값이 있으면 문장에서 찾은 시간보다 먼저 쓴다 (일지는 첫 줄만 보면 크게 적게 잡힘)
        for (Mention m : logHours(text)) found.put(m.subjectName() + "|" + m.type(), m);

        Matcher sm = SENTENCE.matcher(text);
        while (sm.find()) {
            String sentence = sm.group();
            for (Hit h : segments(sentence)) {
                for (Mention m : read(h.name, h.segment, perDay)) {
                    found.putIfAbsent(m.subjectName() + "|" + m.type(), m);
                }
            }
        }
        return check(new ArrayList<>(found.values()), totalHours);
    }

    // ---------------- 문장 → 과목별 구간 ----------------

    private record Hit(int start, int end, String name, String segment) { }

    /** 문장 안의 과목 이름 위치를 찾고, 각 과목 이름부터 다음 과목 이름 전까지를 그 과목의 구간으로 본다 */
    private List<Hit> segments(String sentence) {
        List<Hit> hits = new ArrayList<>();
        for (int i = 0; i < patterns.size(); i++) {
            Matcher m = patterns.get(i).matcher(sentence);
            while (m.find()) {
                int s = m.start(), e = m.end();
                boolean overlap = hits.stream().anyMatch(h -> s < h.end && e > h.start);
                if (!overlap) hits.add(new Hit(s, e, names.get(i), null));
            }
        }
        hits.sort((a, b) -> Integer.compare(a.start, b.start));
        List<Hit> out = new ArrayList<>();
        for (int i = 0; i < hits.size(); i++) {
            Hit h = hits.get(i);
            int stop = i + 1 < hits.size() ? hits.get(i + 1).start : sentence.length();
            // "DB랑 언어는 건너뜀"처럼 과목만 나열된 경우: 나열이 끝나는 과목 뒤까지를 함께 본다
            int j = i;
            while (j + 1 < hits.size()
                    && sentence.substring(hits.get(j).end, hits.get(j + 1).start).replaceAll("[\\s,·랑와과및하고도]", "").isEmpty()) {
                j++;
            }
            if (j > i) {
                int nextAfterList = j + 1 < hits.size() ? hits.get(j + 1).start : sentence.length();
                stop = Math.min(nextAfterList, hits.get(j).end + WINDOW);
            } else {
                stop = Math.min(stop, h.end + WINDOW);
            }
            out.add(new Hit(h.start, h.end, h.name, sentence.substring(h.end, stop)));
        }
        return out;
    }

    // ---------------- 구간 → 언급 ----------------

    private List<Mention> read(String name, String seg, Integer perDay) {
        List<Mention> out = new ArrayList<>();

        if (SKIP.matcher(seg).find()) {
            out.add(new Mention(name, MentionType.SKIPPED, BigDecimal.ZERO, null, false, name + ": 건너뜀(0시간)"));
            return out;   // 건너뛴 과목에 시간·난이도가 같이 나오면 그 말은 다른 과목 이야기일 가능성이 큼
        }

        BigDecimal hours = hours(seg);
        if (hours != null) {
            out.add(new Mention(name, MentionType.HOURS, hours, null, false, name + ": " + plain(hours) + "시간"));
        } else {
            Integer days = days(seg);
            if (days != null && perDay != null) {
                BigDecimal h = BigDecimal.valueOf((long) days * perDay).divide(BigDecimal.valueOf(60), 2, RoundingMode.HALF_UP);
                out.add(new Mention(name, MentionType.HOURS, h, null, true,
                        name + ": " + days + "일 × 하루 " + perDay + "분 ≈ " + plain(h) + "시간(환산)"));
            }
        }

        BigDecimal ratio = ratio(seg);
        if (ratio != null) {
            out.add(new Mention(name, MentionType.RATIO, null, ratio, false, name + ": 전체의 " + plain(ratio) + "%"));
        }

        if (EASY.matcher(seg).find()) {
            out.add(new Mention(name, MentionType.EASY, null, null, false, name + ": 쉬웠다는 언급"));
        } else if (HARD.matcher(seg).find()) {
            out.add(new Mention(name, MentionType.DIFFICULT, null, null, false, name + ": 어려웠다는 언급"));
        }
        return out;
    }

    private BigDecimal hours(String seg) {
        if (HOURS_NOT.matcher(seg).find()) return null;
        Matcher m = HOURS.matcher(seg);
        while (m.find()) {
            if (DAILY_PREFIX.matcher(seg.substring(0, m.start(1))).find()) continue;   // "하루 2시간"은 하루 공부시간
            BigDecimal v = new BigDecimal(m.group(1));
            if (v.signum() > 0 && v.compareTo(BigDecimal.valueOf(999)) <= 0) return v;
        }
        return null;
    }

    private Integer days(String seg) {
        if (!DAYS_CONTEXT.matcher(seg).find() || DAYS_NOT.matcher(seg).find()) return null;
        Integer d = rawDays(seg);
        return d != null && d <= MAX_SUBJECT_DAYS ? d : null;
    }

    private Integer rawDays(String seg) {
        Matcher m = DAYS.matcher(seg);
        if (m.find()) {
            int d = Integer.parseInt(m.group(1));
            if (d >= 1 && d <= 99) return d;
        }
        Matcher k = KO_DAYS.matcher(seg);
        if (k.find()) {
            return switch (k.group(1)) {
                case "이틀" -> 2;
                case "사흘" -> 3;
                case "나흘" -> 4;
                case "닷새" -> 5;
                case "일주일" -> 7;
                default -> 10;   // 열흘
            };
        }
        return null;
    }

    private BigDecimal ratio(String seg) {
        if (!RATIO_CONTEXT.matcher(seg).find() || RATIO_NOT.matcher(seg).find()) return null;
        Matcher m = RATIO.matcher(seg);
        if (m.find()) {
            int v = Integer.parseInt(m.group(1));
            if (v >= 1 && v < 100) return BigDecimal.valueOf(v);   // 한 과목 100% 는 비율 정보가 아님
        }
        if (HALF.matcher(seg).find()) return BigDecimal.valueOf(50);
        return null;
    }

    // ---------------- [11-19] 학습일지 합산 ----------------

    /** 날짜로 시작하는 줄이 MIN_LOG_LINES 줄 이상이면, 과목이 하나만 적힌 줄의 시간을 과목별로 더한다 */
    private List<Mention> logHours(String text) {
        Map<String, Integer> minutes = new LinkedHashMap<>();
        Map<String, Integer> lines = new LinkedHashMap<>();
        int logLines = 0;
        for (String line : text.split("\\R")) {
            Matcher d = LOG_LINE.matcher(line);
            if (!d.find()) continue;
            logLines++;
            String rest = line.substring(d.end());
            Integer min = logMinutes(rest);
            if (min == null || min <= 0 || min > 24 * 60) continue;
            String subject = onlySubject(rest);
            if (subject == null) continue;   // 과목이 없거나(기출 회차 등) 여러 과목이면 나누지 않는다
            minutes.merge(subject, min, Integer::sum);
            lines.merge(subject, 1, Integer::sum);
        }
        if (logLines < MIN_LOG_LINES) return List.of();
        List<Mention> out = new ArrayList<>();
        minutes.forEach((name, m) -> {
            BigDecimal h = BigDecimal.valueOf(m).divide(BigDecimal.valueOf(60), 2, RoundingMode.HALF_UP);
            out.add(new Mention(name, MentionType.HOURS, h, null, false,
                    name + ": 학습일지 " + lines.get(name) + "줄 합산 " + plain(h) + "시간"));
        });
        return out;
    }

    /** 일지 줄 하나의 공부시간(분). 시계 시각 범위("19:00~21:00")처럼 콜론 시각이 둘 이상이면 읽지 않는다 */
    private static Integer logMinutes(String rest) {
        Matcher en = LOG_HM_EN.matcher(rest);
        if (en.find()) return toMinutes(en.group(1), en.group(2));
        Matcher ko = LOG_HM_KO.matcher(rest);
        if (ko.find()) return toMinutes(ko.group(1), ko.group(2));
        Matcher c = LOG_COLON.matcher(rest);
        if (c.find()) {
            int h = Integer.parseInt(c.group(1)), m = Integer.parseInt(c.group(2));
            return c.find() ? null : h * 60 + m;
        }
        Matcher mi = LOG_MIN.matcher(rest);
        return mi.find() ? Integer.parseInt(mi.group(1)) : null;
    }

    private static Integer toMinutes(String hours, String mins) {
        int total = new BigDecimal(hours).multiply(BigDecimal.valueOf(60)).intValue();
        return mins == null ? total : total + Integer.parseInt(mins);
    }

    /** 줄에 적힌 과목이 정확히 하나면 그 과목명, 아니면 null */
    private String onlySubject(String rest) {
        java.util.Set<String> hit = new java.util.LinkedHashSet<>();
        for (int i = 0; i < patterns.size(); i++) {
            if (patterns.get(i).matcher(rest).find()) hit.add(names.get(i));
        }
        return hit.size() == 1 ? hit.iterator().next() : null;
    }

    // ---------------- 검사 ----------------

    /** 과목 시간 합 > 총 공부시간, 또는 비율 합 > 100% 이면 그 종류 값을 모두 버린다 */
    private List<Mention> check(List<Mention> list, BigDecimal totalHours) {
        BigDecimal hourSum = list.stream().filter(m -> m.type() == MentionType.HOURS)
                .map(Mention::hours).reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal ratioSum = list.stream().filter(m -> m.type() == MentionType.RATIO)
                .map(Mention::ratioPercent).reduce(BigDecimal.ZERO, BigDecimal::add);
        boolean dropHours = totalHours != null && hourSum.compareTo(totalHours) > 0;
        boolean dropRatio = ratioSum.compareTo(BigDecimal.valueOf(100)) > 0;
        return list.stream()
                .filter(m -> !(dropHours && m.type() == MentionType.HOURS))
                .filter(m -> !(dropRatio && m.type() == MentionType.RATIO))
                .toList();
    }

    private static String plain(BigDecimal v) {
        return v.stripTrailingZeros().toPlainString();
    }
}
