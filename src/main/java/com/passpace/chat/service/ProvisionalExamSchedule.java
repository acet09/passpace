package com.passpace.chat.service;

import java.time.LocalDate;

/**
 * 2027년 공식 일정 미공개 시의 데모 목표일. 2026년 공고의 월/일만 2027년으로 옮긴다.
 * 이 값은 시험일 예측이나 실제 시험 시행 공고가 절대 아니다.
 */
public final class ProvisionalExamSchedule {
    private ProvisionalExamSchedule() { }
    public record Suggestion(LocalDate targetDate, String notice, String basisUrl) { }

    public static Suggestion forGoal(String certificationName, LocalDate today) {
        if (certificationName == null || today == null) return null;
        if (today.getYear() > 2027) return null;
        LocalDate date;
        String basis;
        String url;
        if (certificationName.contains("SQLD")) {
            date = LocalDate.of(2027, 3, 7);
            basis = "2026 SQLD 제60회 시험일(3월 7일)의 월/일을 2027년에 가상 적용";
            url = "https://www.dataq.or.kr/";
        } else if (certificationName.contains("정보처리기사") && certificationName.contains("실기")) {
            date = LocalDate.of(2027, 5, 6);
            basis = "2026 기사 1회 실기 시험기간 마지막 날(5월 6일)을 2027년에 가상 적용";
            url = "https://www.q-net.or.kr/crf005.do?id=crf00503s02&jmCd=1320&jmInfoDivCcd=B0";
        } else if (certificationName.contains("정보처리기사")) {
            date = LocalDate.of(2027, 3, 3);
            basis = "2026 기사 1회 필기 시험기간 마지막 날(3월 3일)을 2027년에 가상 적용";
            url = "https://www.q-net.or.kr/crf005.do?id=crf00503s02&jmCd=1320&jmInfoDivCcd=B0";
        } else return null;
        if (!date.isAfter(today)) return null;
        return new Suggestion(date, "2027년 공식 시험일 아님 — " + basis + ". 공식 공고 후 반드시 변경하세요.", url);
    }
}
