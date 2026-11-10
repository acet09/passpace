package com.passpace.collect.repository;

import com.passpace.collect.dto.CollectDtos.QualityResult;
import com.passpace.common.review.ExtractedReview;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;

/** [용성] PASS_REVIEWS JDBC 구현 */
@Repository
public class JdbcPassReviewRepository implements PassReviewRepository {

    private final JdbcTemplate jdbc;

    public JdbcPassReviewRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public boolean existsByUrl(String sourceUrl) {
        Integer n = jdbc.queryForObject("SELECT COUNT(*) FROM PASS_REVIEWS WHERE source_url = ?", Integer.class, sourceUrl);
        return n != null && n > 0;
    }

    @Override
    public void insert(long sourceId, long certificationId, String sourceUrl, LocalDate postedAt, String authorHash,
                       ExtractedReview r, QualityResult q) {
        // daily_hours(원본, VARCHAR)는 "2.5" 같은 표시용, daily_minutes(확장)는 계산용 숫자
        String dailyHoursText = r.dailyMinutes() == null ? null
                : String.valueOf(Math.round(r.dailyMinutes() / 6.0) / 10.0).replaceAll("\\.0$", "");
        jdbc.update("""
                INSERT INTO PASS_REVIEWS (source_id, certification_id, exam_type, major_type, source_url, posted_at,
                       proof_yn, prep_days, total_hours, daily_hours, study_subjects, evidence_text,
                       review_status, exclude_reason, pass_yn, daily_minutes, exam_year, round_no, study_method, author_hash, collected_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
                """,
                sourceId, certificationId,
                r.examType() == null ? null : r.examType().name(),
                r.majorType() == null ? null : r.majorType().name(),
                sourceUrl, postedAt,
                r.proof() ? "Y" : "N",
                r.prepDays(), r.totalHours(), dailyHoursText, r.studySubjects(), r.evidenceText(),
                q.reviewStatus(), q.excludeReason(),
                r.passed() == null ? null : (r.passed() ? "Y" : "N"),
                r.dailyMinutes(), r.examYear(), r.roundNo(),
                r.studyMethod() == null ? null : r.studyMethod().name(),
                authorHash);
    }

    @Override
    public int countBySource(long sourceId) {
        Integer n = jdbc.queryForObject("SELECT COUNT(*) FROM PASS_REVIEWS WHERE source_id = ?", Integer.class, sourceId);
        return n == null ? 0 : n;
    }

    @Override
    public int deleteBySource(long sourceId) {
        return jdbc.update("DELETE FROM PASS_REVIEWS WHERE source_id = ?", sourceId);
    }

    @Override
    public java.util.List<CrawledRow> listBySources(java.util.List<Long> sourceIds) {
        if (sourceIds.isEmpty()) return java.util.List.of();
        String in = String.join(",", java.util.Collections.nCopies(sourceIds.size(), "?"));
        return jdbc.query("SELECT source_url, source_id, certification_id, review_status, pass_yn, exam_type, major_type,"
                        + " prep_days, daily_minutes, total_hours FROM PASS_REVIEWS WHERE source_id IN (" + in + ")",
                (rs, n) -> new CrawledRow(rs.getString("source_url"), rs.getLong("source_id"), rs.getLong("certification_id"),
                        rs.getString("review_status"), rs.getString("pass_yn"), rs.getString("exam_type"),
                        rs.getString("major_type"), (Integer) rs.getObject("prep_days", Integer.class),
                        (Integer) rs.getObject("daily_minutes", Integer.class),
                        rs.getBigDecimal("total_hours") == null ? null : rs.getBigDecimal("total_hours").stripTrailingZeros().toPlainString()),
                sourceIds.toArray());
    }
}
