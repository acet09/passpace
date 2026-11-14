package com.passpace.repository;

import com.passpace.dto.collect.CollectDtos.QualityResult;
import com.passpace.domain.ExtractedReview;

import java.time.LocalDate;

/** [용성] PASS_REVIEWS 쓰기 (원문은 저장하지 않는다 - 구조화 값 + 요약문 + URL + 작성일 + 작성자 해시) */
public interface PassReviewRepository {

    boolean existsByUrl(String sourceUrl);

    void insert(long sourceId, long certificationId, String sourceUrl, LocalDate postedAt, String authorHash,
                ExtractedReview review, QualityResult quality);

    /**
     * [11-14] 출처 번호 없이(NULL) 저장 - DATA_SOURCES 행이 없는 새 출처(네이버 블로그·카페) 전용.
     * 기존 insert(long …)는 그대로 두고 추가만 했다. sourceId 가 null 이 아니면 그 번호로 저장한다.
     */
    default void insertWithNullableSource(Long sourceId, long certificationId, String sourceUrl, LocalDate postedAt,
                                          String authorHash, ExtractedReview review, QualityResult quality) {
        throw new UnsupportedOperationException("insertWithNullableSource 미구현");
    }

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
