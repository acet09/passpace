package com.passpace.service;

import java.util.Optional;
import java.util.regex.Pattern;
import java.util.LinkedHashSet;
import java.util.Set;

/**
 * [용성] 글이 어느 자격증 후기인지 판단 (기획안 7.1.1 "수집 대상 자격증만").
 * 결과는 CERTIFICATIONS.source_exam_code 값: "1320"(정보처리기사) / "SQLD" / "CA1"(컴활 1급) / "ADSP".
 * 둘 이상 나오면 제목 기준으로, 제목에도 둘 이상 있거나 없으면 판단 보류(Optional.empty).
 * "정보처리산업기사·기능사", "컴활 2급", "SQLP", "ADP"(데이터분석 전문가), 리눅스마스터는 다른 자격증이므로 제외한다.
 * [11-14] 컴활 1급·ADsP 추가. CA1·ADSP 코드는 팀 합의 전 임시값 (db/09_review_sources.sql 과 같아야 한다)
 * [11-26] 빅데이터분석기사(BIGDATA)·전산회계 1급(ACC1)·2급(ACC2) 추가. 다른 자격증과 함께 쓴 후기가 많아 그 자격증 구간만 잘라 판정(textFor).
 * [11-26] 산업안전기사(SAFETY)·컴활 2급(CA2) 추가 (db/13_new_certifications.sql 과 같아야 한다).
 *         산업안전산업기사·건설안전기사는 다른 자격증이므로 지운 뒤 찾는다. 제목에 자격증이 둘 이상이면 판단 보류(기존 규칙).
 */
public final class CertificateDetector {

    static final String ENGINEER = "1320";
    static final String SQLD = "SQLD";
    static final String COMPUTER1 = "CA1";
    static final String ADSP = "ADSP";
    static final String SAFETY = "SAFETY";
    static final String COMPUTER2_CODE = "CA2";
    static final String BIGDATA = "BIGDATA";
    static final String ACCOUNTING1 = "ACC1";
    static final String ACCOUNTING2 = "ACC2";
    /** [11-26] 다른 자격증과 섞인 후기에서 그 자격증 구간만 잘라 판정하는 자격증 (기존 4종 판정은 바꾸지 않음) */
    public static final java.util.Set<String> SEGMENTED = java.util.Set.of(BIGDATA, ACCOUNTING1, ACCOUNTING2);
    /** [11-26] 필기(이론+실무 1회 시험)만 있는 자격증: 시험 구분을 WRITTEN 으로 고정 */
    private static final java.util.Set<String> WRITTEN_ONLY = java.util.Set.of(SQLD, ADSP, ACCOUNTING1, ACCOUNTING2);

    private static final Pattern OTHER_GRADE = Pattern.compile("정보처리\\s*(?:산업기사|기능사)|정처산기|정처기능사");
    private static final Pattern ENGINEER_WORD = Pattern.compile("정보\\s*처리\\s*기사|정처기");
    private static final Pattern SQLD_WORD = Pattern.compile("(?i)\\bSQLD\\b|SQL\\s*개발자");
    /** 컴활 2급만 언급한 글은 제외: "컴활 2급"·"컴퓨터활용능력 2급" 을 지운 뒤 1급 표현을 찾는다 */
    private static final Pattern COMPUTER2 = Pattern.compile("(?:컴퓨터\\s*활용\\s*능력|컴활)\\s*2\\s*급");
    private static final Pattern COMPUTER1_WORD = Pattern.compile("(?:컴퓨터\\s*활용\\s*능력|컴활)\\s*1\\s*급");
    /** ADP(데이터분석 전문가)는 다른 자격증: "준전문가" 만 ADsP 로 본다 */
    private static final Pattern ADSP_WORD = Pattern.compile("(?i)\\bADsP\\b|데이터\\s*분석\\s*준\\s*전문가");

    /** [11-26] 산업안전기사. 산업안전"산업"기사·건설안전기사는 다른 자격증 */
    private static final Pattern SAFETY_OTHER = Pattern.compile("산업\\s*안전\\s*산업\\s*기사|건설\\s*안전\\s*기사");
    private static final Pattern SAFETY_WORD = Pattern.compile("산업\\s*안전\\s*기사|산안기");

    /** [11-26] 빅데이터분석기사·전산회계 1급·2급 ("전산회계 1·2급" 처럼 함께 쓰면 둘 다) */
    private static final Pattern BIGDATA_WORD = Pattern.compile("빅\\s*데이터\\s*분석\\s*기사|빅분기");
    private static final Pattern ACC1_WORD = Pattern.compile("전산\\s*회계\\s*1\\s*급|전회\\s*1\\s*급");
    private static final Pattern ACC2_WORD = Pattern.compile("전산\\s*회계\\s*2\\s*급|전회\\s*2\\s*급");
    private static final Pattern ACC_BOTH = Pattern.compile("전산\\s*회계\\s*1\\s*급?\\s*[·.,/&및와과]\\s*2\\s*급");

    private CertificateDetector() {
    }

    public static Optional<String> detect(String title, String text) {
        Optional<String> byTitle = decide(title == null ? "" : title);
        if (byTitle.isPresent()) return byTitle;
        String t = title == null ? "" : title;
        if (found(t).size() > 1) return Optional.empty();     // 제목에 둘 이상 → 보류
        return decide(text == null ? "" : text);
    }

    private static Optional<String> decide(String s) {
        Set<String> f = found(s);
        return f.size() == 1 ? Optional.of(f.iterator().next()) : Optional.empty();
    }

    private static Set<String> found(String s) {
        Set<String> f = new LinkedHashSet<>();
        if (hasEngineer(s)) f.add(ENGINEER);
        if (hasSqld(s)) f.add(SQLD);
        if (COMPUTER1_WORD.matcher(COMPUTER2.matcher(s).replaceAll(" ")).find()) f.add(COMPUTER1);
        if (ADSP_WORD.matcher(s).find()) f.add(ADSP);
        if (COMPUTER2.matcher(s).find()) f.add(COMPUTER2_CODE);
        if (SAFETY_WORD.matcher(SAFETY_OTHER.matcher(s).replaceAll(" ")).find()) f.add(SAFETY);
        if (BIGDATA_WORD.matcher(s).find()) f.add(BIGDATA);
        if (ACC1_WORD.matcher(s).find()) f.add(ACCOUNTING1);
        if (ACC2_WORD.matcher(s).find()) f.add(ACCOUNTING2);
        if (ACC_BOTH.matcher(s).find()) {
            f.add(ACCOUNTING1);
            f.add(ACCOUNTING2);
        }
        return f;
    }

    /** [11-26] 필기만 있는 자격증인가 (SQLD·ADsP·전산회계 1·2급) */
    public static boolean writtenOnly(String code) {
        return code != null && WRITTEN_ONLY.contains(code);
    }

    /**
     * [11-26] 판정에 쓸 본문. SEGMENTED 자격증이고 본문에 다른 자격증이 함께 나오면 그 자격증 구간만,
     * 아니면 본문 그대로. 다른 자격증의 공부시간이 섞여 들어가지 않게 하기 위함 (구간에 시간이 없으면 품질 검사에서 제외됨).
     */
    public static String textFor(String code, String title, String text) {
        if (code == null || text == null || !SEGMENTED.contains(code)) return text;
        Set<String> all = found(text);
        all.remove(code);
        return all.isEmpty() ? text : segment(code, title, text);
    }

    /** 본문을 줄·문장으로 나눠, 가장 최근에 언급된 자격증이 code 인 구간만 모은다. 제목이 code 하나면 첫 언급 전도 code 구간 */
    static String segment(String code, String title, String text) {
        boolean own = code.equals(decide(title == null ? "" : title).orElse(null));
        StringBuilder sb = new StringBuilder();
        for (String piece : text.split("\\n+|(?<=[.!?。])\\s+")) {
            Set<String> f = found(piece);
            if (f.contains(code)) own = true;
            else if (!f.isEmpty()) own = false;
            if (own) sb.append(piece).append('\n');
        }
        return sb.toString().trim();
    }

    private static boolean hasEngineer(String s) {
        String cleaned = OTHER_GRADE.matcher(s).replaceAll(" ");
        return ENGINEER_WORD.matcher(cleaned).find();
    }

    private static boolean hasSqld(String s) {
        return SQLD_WORD.matcher(s).find();
    }
}
