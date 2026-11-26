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

    // ---------------- [11-23] 본문 재판정 (이미 저장한 행을 다시 판정해 같은 행을 갱신, 테이블 구조 변경 없음) ----------------

    /** 재판정 대상 1건 (원문 없음). certCode 는 CERTIFICATIONS.source_exam_code */
    record RejudgeTarget(long reviewId, String url, long certificationId, String certCode, LocalDate postedAt) {
    }

    /**
     * 재판정 대상 목록.
     * @param mode NAVER_BLOG = 네이버 블로그 요약문 후기(본문을 아직 안 읽은 것, 작성일 notBefore 이후 또는 작성일 없음)
     *             NAVER_CAFE = 네이버 카페 요약문 후기(본문을 아직 안 읽은 것, 작성일은 본문에서 확인)
     *             NO_TIME    = 본문 크롤링 후기 중 "시간 정보 없음"으로 제외된 것
     */
    default java.util.List<RejudgeTarget> listForRejudge(String mode, LocalDate notBefore, int limit) {
        throw new UnsupportedOperationException("listForRejudge 미구현");
    }

    /** 재판정 결과로 같은 행의 추출값·상태를 갱신한다 (source_id·source_url·author_hash 는 그대로, 작성일은 비어 있을 때만 채움) */
    default int updateFromBody(long reviewId, LocalDate postedAt, ExtractedReview review, QualityResult quality) {
        throw new UnsupportedOperationException("updateFromBody 미구현");
    }
}
