package com.passpace.common.stats;

import java.math.BigDecimal;

/**
 * [공통 계약] 통계 계산에 쓰는 후기 1건 (PASS_REVIEWS 의 VALID 행).
 *
 * @param passed        합격 true / 불합격 false / 모름 null
 * @param dailyMinutes  하루 공부시간(분)
 * @param totalHours    총 공부시간(시간)
 * @param prepDays      준비 기간(일)
 * @param majorType     전공 구분 코드 문자열
 * @param studyMethod   학습 방식 코드 문자열
 * @param studySubjects 언급 과목
 * @param evidenceText  근거 1문장
 * @param sourceUrl     출처 URL
 */
public record ReviewSample(Boolean passed, Integer dailyMinutes, BigDecimal totalHours, Integer prepDays,
                           String majorType, String studyMethod, String studySubjects,
                           String evidenceText, String sourceUrl) {
}
