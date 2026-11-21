package com.passpace.domain;

import com.passpace.constant.ExamType;
import com.passpace.constant.MajorType;

/**
 * [공통 계약] 유사 집단 후기 조회 조건.
 *
 * @param certificationId CERTIFICATIONS.certification_id
 * @param examType        필기·실기
 * @param majorType       전공 구분 (null 이면 전공 구분 없이 전체)
 * @param minPrepDays     준비 기간 최소(일)
 * @param maxPrepDays     준비 기간 최대(일)
 */
public record StatsCondition(long certificationId, ExamType examType, MajorType majorType,
                             int minPrepDays, int maxPrepDays) {
}
