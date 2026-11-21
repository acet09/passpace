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
 */
public final class CertificateDetector {

    static final String ENGINEER = "1320";
    static final String SQLD = "SQLD";
    static final String COMPUTER1 = "CA1";
    static final String ADSP = "ADSP";

    private static final Pattern OTHER_GRADE = Pattern.compile("정보처리\\s*(?:산업기사|기능사)|정처산기|정처기능사");
    private static final Pattern ENGINEER_WORD = Pattern.compile("정보\\s*처리\\s*기사|정처기");
    private static final Pattern SQLD_WORD = Pattern.compile("(?i)\\bSQLD\\b|SQL\\s*개발자");
    /** 컴활 2급만 언급한 글은 제외: "컴활 2급"·"컴퓨터활용능력 2급" 을 지운 뒤 1급 표현을 찾는다 */
    private static final Pattern COMPUTER2 = Pattern.compile("(?:컴퓨터\\s*활용\\s*능력|컴활)\\s*2\\s*급");
    private static final Pattern COMPUTER1_WORD = Pattern.compile("(?:컴퓨터\\s*활용\\s*능력|컴활)\\s*1\\s*급");
    /** ADP(데이터분석 전문가)는 다른 자격증: "준전문가" 만 ADsP 로 본다 */
    private static final Pattern ADSP_WORD = Pattern.compile("(?i)\\bADsP\\b|데이터\\s*분석\\s*준\\s*전문가");

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
        return f;
    }

    private static boolean hasEngineer(String s) {
        String cleaned = OTHER_GRADE.matcher(s).replaceAll(" ");
        return ENGINEER_WORD.matcher(cleaned).find();
    }

    private static boolean hasSqld(String s) {
        return SQLD_WORD.matcher(s).find();
    }
}
