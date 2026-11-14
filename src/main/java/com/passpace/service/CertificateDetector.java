package com.passpace.service;

import java.util.Optional;
import java.util.regex.Pattern;

/**
 * [용성] 글이 어느 자격증 후기인지 판단 (기획안 7.1.1 "수집 대상 자격증만").
 * 결과는 CERTIFICATIONS.source_exam_code 값: "1320"(정보처리기사) / "SQLD".
 * 둘 다 나오면 제목 기준으로, 제목에도 둘 다 있거나 없으면 판단 보류(Optional.empty).
 * "정보처리산업기사·기능사"는 다른 자격증이므로 제외한다.
 */
public final class CertificateDetector {

    static final String ENGINEER = "1320";
    static final String SQLD = "SQLD";

    private static final Pattern OTHER_GRADE = Pattern.compile("정보처리\\s*(?:산업기사|기능사)|정처산기|정처기능사");
    private static final Pattern ENGINEER_WORD = Pattern.compile("정보\\s*처리\\s*기사|정처기");
    private static final Pattern SQLD_WORD = Pattern.compile("(?i)\\bSQLD\\b|SQL\\s*개발자");

    private CertificateDetector() {
    }

    public static Optional<String> detect(String title, String text) {
        Optional<String> byTitle = decide(title == null ? "" : title);
        if (byTitle.isPresent()) return byTitle;
        String t = title == null ? "" : title;
        if (hasEngineer(t) && hasSqld(t)) return Optional.empty();     // 제목에 둘 다 → 보류
        return decide(text == null ? "" : text);
    }

    private static Optional<String> decide(String s) {
        boolean engineer = hasEngineer(s);
        boolean sqld = hasSqld(s);
        if (engineer && !sqld) return Optional.of(ENGINEER);
        if (sqld && !engineer) return Optional.of(SQLD);
        return Optional.empty();
    }

    private static boolean hasEngineer(String s) {
        String cleaned = OTHER_GRADE.matcher(s).replaceAll(" ");
        return ENGINEER_WORD.matcher(cleaned).find();
    }

    private static boolean hasSqld(String s) {
        return SQLD_WORD.matcher(s).find();
    }
}
