package com.passpace.service;

import com.passpace.domain.ExtractedReview;

import java.util.ArrayList;
import java.util.List;

/**
 * [용성] 근거 문장 대신 저장하는 "Java 요약문" (사용자 결정: 원문 문장 저장 대신 요약문).
 * 원문 표현을 한 글자도 옮기지 않고, 추출된 구조화 값만으로 문장을 만든다.
 * 예) "비전공 · 2025년 2회 필기 합격 · 준비 60일 · 하루 2시간 30분 · 기출 위주 · 언급 과목: 데이터베이스 구축"
 *
 * 동건의 챗봇은 이 문장을 [근거 n] 으로 그대로 보여 주고, 원글은 source_url 링크로 안내한다.
 */
public final class ReviewSummary {

    private ReviewSummary() {
    }

    public static String of(ExtractedReview r) {
        List<String> parts = new ArrayList<>();
        if (r.majorType() != null) parts.add(r.majorType().getLabel());

        StringBuilder exam = new StringBuilder();
        if (r.examYear() != null) exam.append(r.examYear()).append("년 ");
        if (r.roundNo() != null) exam.append(r.roundNo()).append("회 ");
        if (r.examType() != null) exam.append(r.examType().getLabel()).append(' ');
        if (r.passed() != null) exam.append(r.passed() ? "합격" : "불합격");
        else exam.append("결과 미확인");
        parts.add(exam.toString().strip());

        if (r.prepDays() != null) parts.add("준비 " + r.prepDays() + "일");
        if (r.dailyMinutes() != null) parts.add("하루 " + hm(r.dailyMinutes()));
        if (r.totalHours() != null) parts.add("총 " + r.totalHours().stripTrailingZeros().toPlainString() + "시간");
        if (r.studyMethod() != null) parts.add(r.studyMethod().getLabel());
        if (r.studySubjects() != null) parts.add("언급 과목: " + r.studySubjects().replace(",", ", "));
        if (r.proof()) parts.add("합격 인증 언급");
        return String.join(" · ", parts);
    }

    /** 150 → "2시간 30분", 120 → "2시간", 40 → "40분" */
    static String hm(int minutes) {
        int h = minutes / 60, m = minutes % 60;
        if (h == 0) return m + "분";
        return m == 0 ? h + "시간" : h + "시간 " + m + "분";
    }
}
