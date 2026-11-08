package com.passpace.common.code;

/**
 * [공통 계약] 후기 검토 상태. 사용 컬럼: PASS_REVIEWS.review_status
 * 통계에는 VALID 만 사용한다.
 */
public enum ReviewStatus {
    VALID,      // 통계에 사용
    EXCLUDED,   // 제외 (exclude_reason 에 이유 기록)
    PENDING     // 사람이 확인해야 함
}
