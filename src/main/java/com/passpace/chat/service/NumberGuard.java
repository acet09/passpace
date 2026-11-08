package com.passpace.chat.service;

import java.math.BigDecimal;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [동건] 처리 ⑤ 숫자 검증 (Spring 없이 테스트 가능한 순수 클래스)
 * LLM 답변에 나온 숫자가 Java 가 보낸 자료에 실제로 있는 숫자인지 확인한다.
 * → 원문·통계에 없는 시간·합격률을 LLM 이 지어내는 것을 막는다 (기획안 5.5)
 * 0~12 는 "1단계", "3월", "2주차" 같은 서수·월로 자주 쓰여 항상 허용한다.
 */
public class NumberGuard {

    private static final Pattern NUMBER = Pattern.compile("\\d+(?:\\.\\d+)?");

    /** 자료 텍스트에 들어 있는 모든 숫자 + 0~12 */
    public Set<String> allowedNumbers(String payload) {
        Set<String> result = numbersIn(payload);
        for (int i = 0; i <= 12; i++) result.add(String.valueOf(i));
        return result;
    }

    /** 허용되지 않은 숫자 목록 (비어 있으면 통과) */
    public Set<String> findViolations(String answer, Set<String> allowed) {
        Set<String> violations = numbersIn(answer);
        violations.removeAll(allowed);
        return violations;
    }

    /** "1,234" → 1234, "2.50" → 2.5, "03" → 3 으로 맞춘 숫자들 */
    static Set<String> numbersIn(String text) {
        Set<String> found = new LinkedHashSet<>();
        if (text == null) return found;
        Matcher m = NUMBER.matcher(text.replaceAll("(?<=\\d),(?=\\d{3}(?:\\D|$))", ""));
        while (m.find()) found.add(normalize(m.group()));
        return found;
    }

    static String normalize(String number) {
        try {
            return new BigDecimal(number.replace(",", "")).stripTrailingZeros().toPlainString();
        } catch (NumberFormatException e) {
            return number;
        }
    }
}
