package com.passpace.repository;

import com.passpace.domain.ReviewSample;
import com.passpace.domain.StatsCondition;

import java.util.List;

/**
 * [공통 계약] 후기 조회. PASS_REVIEWS 구조를 아는 용성이 구현하고, 동건(챗봇)이 사용한다.
 *  - 실제 구현: collect.stats.JdbcReviewStatsQuery  (프로필 fake 가 아닐 때)
 *  - 가짜 구현: chat.fake.FakeReviewStatsQuery     (프로필 fake 일 때, DB 후기 없이 챗봇 개발용)
 */
public interface ReviewStatsQuery {

    /** 조건에 맞는 VALID 후기 목록 (합격·불합격 모두) */
    List<ReviewSample> findSamples(StatsCondition condition);
}
