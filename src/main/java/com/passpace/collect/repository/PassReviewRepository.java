package com.passpace.collect.repository;

import com.passpace.collect.dto.CollectDtos.QualityResult;
import com.passpace.common.review.ExtractedReview;

import java.time.LocalDate;

/** [용성] PASS_REVIEWS 쓰기 (원문은 저장하지 않는다 - 구조화 값 + 요약문 + URL + 작성일 + 작성자 해시) */
public interface PassReviewRepository {

    boolean existsByUrl(String sourceUrl);

    void insert(long sourceId, long certificationId, String sourceUrl, LocalDate postedAt, String authorHash,
                ExtractedReview review, QualityResult quality);

    /** 출처별 후기 수 (초기화 전 미리보기) */
    int countBySource(long sourceId);

    /** 해당 출처 후기를 모두 삭제하고 지운 수를 돌려준다 (크롤링 출처에만 사용) */
    int deleteBySource(long sourceId);

    /** 복구율 비교용: 크롤링 후기의 핵심 값 (원문 없음) */
    record CrawledRow(String url, long sourceId, long certificationId, String status, String passYn, String examType,
                      String majorType, Integer prepDays, Integer dailyMinutes, String totalHours) {
    }

    /** 해당 출처들의 후기 핵심 값 목록 */
    java.util.List<CrawledRow> listBySources(java.util.List<Long> sourceIds);
}
