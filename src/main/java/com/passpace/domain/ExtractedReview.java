package com.passpace.domain;

import com.passpace.constant.ExamType;
import com.passpace.constant.MajorType;
import com.passpace.constant.StudyMethod;

import java.math.BigDecimal;

/**
 * [공통 계약] 후기 원문 1건에서 뽑아낸 구조화 값. 원문에 없으면 null (추측 금지).
 * 원문 텍스트는 이 객체에 넣지 않는다 → 구조화 값으로 만든 요약문(evidenceText)만 남긴다.
 *
 * @param passed        합격 true / 불합격 false / 모름 null
 * @param examType      필기·실기
 * @param examYear      응시 연도
 * @param roundNo       응시 회차
 * @param majorType     전공 구분
 * @param prepDays      준비 기간(일)  ※ "한 달 준비"는 30일이지 총 공부시간이 아님
 * @param dailyMinutes  하루 공부시간(분)
 * @param totalHours    총 공부시간(시간)
 * @param studySubjects 언급한 과목 (쉼표 구분)
 * @param studyMethod   학습 방식
 * @param proof         합격 인증(합격 화면·점수 언급) 여부
 * @param evidenceText  근거 요약문 (구조화 값으로 만든 문장, 원문 문장 아님)
 */
public record ExtractedReview(
        Boolean passed,
        ExamType examType,
        Integer examYear,
        Integer roundNo,
        MajorType majorType,
        Integer prepDays,
        Integer dailyMinutes,
        BigDecimal totalHours,
        String studySubjects,
        StudyMethod studyMethod,
        boolean proof,
        String evidenceText
) {
}
