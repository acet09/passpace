package com.passpace.common.reference;

import com.passpace.common.code.ExamType;
import com.passpace.common.code.MajorType;

import java.util.List;

/**
 * [공통 계약] 자격증·시험구분별 참고 학습시간 (기획안 3.2③ "참고 학습량 적용", 7.1.4 "표본 수와 함께 제공").
 *
 * 제공: 용성 (collect/stats/JdbcStudyReferenceQuery, STUDY_REFERENCE_STATS 조회)
 * 사용: 동건 (통합 학습계획의 과목별 기준시간)
 *
 * @param certificationId 자격증 ID
 * @param examType        시험 구분
 * @param appliedMajor    실제로 적용된 전공 집단 (null = 전공 구분 없는 전체 값)
 * @param totalHours      자격증 전체 참고 학습시간
 * @param sampleCount     totalHours 의 근거 표본 수
 * @param minHours        표본 최소 (VERIFIED 일 때만)
 * @param maxHours        표본 최대 (VERIFIED 일 때만)
 * @param verified        true = 합격 후기 유효 표본(최소 표본 이상)의 실측 평균 / false = 소수 사례 기반 잠정값
 * @param sourceNote      산출 근거·한계 설명 (화면에 그대로 표시 가능)
 * @param subjects        과목별 참고 시간 (과목 순서대로)
 */
public record StudyReference(long certificationId, ExamType examType, MajorType appliedMajor,
                             double totalHours, int sampleCount, Double minHours, Double maxHours,
                             boolean verified, String sourceNote, List<SubjectHours> subjects) {

    /**
     * @param subjectId   CERTIFICATION_SUBJECTS ID
     * @param subjectName 과목명
     * @param hours       과목 참고 시간
     * @param basis       이 값이 어떻게 나왔는지 (예: "총시간 실측 12건 × 과목 비율(잠정)")
     */
    public record SubjectHours(long subjectId, String subjectName, double hours, String basis) {
    }
}
