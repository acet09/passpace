package com.passpace.dto.collect;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/**
 * [용성·11-14] 관리자 "수집 데이터" 화면용 조회 결과 (읽기 전용, 저장 없음)
 *  GET /admin/collect/data/summary · GET /admin/collect/data/reviews
 */
public final class CollectDataView {

    private CollectDataView() {
    }

    /** 표 한 칸: key(출처 이름 또는 자격증 이름) × status(VALID·PENDING·EXCLUDED) = count */
    public record CountRow(String key, String status, long count) {
    }

    /** 요약: 출처별 · 자격증별 건수, 전체 건수, 마지막 수집 시각 */
    public record Summary(List<CountRow> bySource, List<CountRow> byCert, long total, LocalDateTime lastCollectedAt) {
    }

    /** 후기 1건 (원문 없음, 구조화 값 + 요약문 + 주소) */
    public record ReviewRow(long reviewId, String source, String certName, String examType, String reviewStatus,
                            String excludeReason, String passYn, String majorType, Integer prepDays,
                            Integer dailyMinutes, BigDecimal totalHours, String studySubjects, String studyMethod,
                            String evidenceText, LocalDate postedAt, String sourceUrl, LocalDateTime collectedAt) {
    }

    /** 후기 목록 한 쪽 */
    public record ReviewPage(long total, int page, int size, List<ReviewRow> rows) {
    }
}
