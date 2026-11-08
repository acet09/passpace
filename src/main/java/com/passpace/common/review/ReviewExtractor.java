package com.passpace.common.review;

/**
 * [공통 계약] 후기 원문 → 구조화 값 추출기.
 *  - 1차 구현: 용성의 규칙(정규식) 기반 {@code RuleBasedReviewExtractor}
 *  - 확장: 동건이 LLM 으로 분류하는 구현을 추가할 수 있다 (같은 인터페이스라 용성 코드는 그대로)
 */
public interface ReviewExtractor {

    /**
     * @param title 글 제목
     * @param text  본문 (메모리에서만 사용, 저장 금지)
     */
    ExtractedReview extract(String title, String text);
}
