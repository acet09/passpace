package com.passpace.repository;

import com.passpace.dto.collect.CollectDtos.QualityResult;
import com.passpace.domain.ExtractedReview;
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

    /** [11-14] insert 와 같은 SQL, source_id 만 NULL 허용 (DATA_SOURCES 행이 없는 새 출처용) */
    @Override
    public void insertWithNullableSource(Long sourceId, long certificationId, String sourceUrl, LocalDate postedAt,
                                         String authorHash, ExtractedReview r, QualityResult q) {
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

    /** [11-23] 네이버 블로그 요약문 후기 중 본문을 아직 읽지 않은 행 (ReviewQualityChecker.checkSnippet 의 사유로 구분) */
    static final String SNIPPET_REASONS = "('요약문만 수집', '작성일 없음·요약문만 수집')";

    @Override
    public java.util.List<RejudgeTarget> listForRejudge(String mode, LocalDate notBefore, int limit) {
        String where;
        Object[] args;
        if ("NAVER_BLOG".equals(mode)) {
            where = "p.source_id IS NULL AND p.source_url LIKE 'https://blog.naver.com/%' AND p.review_status = 'PENDING'"
                    + " AND p.exclude_reason IN " + SNIPPET_REASONS + " AND (p.posted_at IS NULL OR p.posted_at >= ?)"
                    + " ORDER BY (p.pass_yn = 'Y') DESC, p.posted_at DESC, p.review_id";
            args = new Object[]{notBefore, limit};
        } else if ("NAVER_CAFE".equals(mode)) {
            // 카페는 검색 API 가 작성일을 주지 않아(posted_at NULL) 미리 거르지 않는다. 본문 응답의 작성일로 3년 검사
            where = "p.source_id IS NULL AND p.source_url LIKE 'https://cafe.naver.com/%' AND p.review_status = 'PENDING'"
                    + " AND p.exclude_reason IN " + SNIPPET_REASONS
                    + " ORDER BY (p.pass_yn = 'Y') DESC, p.review_id";
            args = new Object[]{limit};
        } else if ("NO_TIME".equals(mode)) {
            where = "p.source_id IS NOT NULL AND p.review_status = 'EXCLUDED' AND p.exclude_reason = '시간 정보 없음'"
                    + " ORDER BY p.review_id";
            args = new Object[]{limit};
        } else {
            throw new IllegalArgumentException("알 수 없는 재판정 대상: " + mode);
        }
        return jdbc.query("SELECT p.review_id, p.source_url, p.certification_id, c.source_exam_code, p.posted_at"
                        + " FROM PASS_REVIEWS p JOIN CERTIFICATIONS c ON c.certification_id = p.certification_id"
                        + " WHERE " + where + " LIMIT ?",
                (rs, n) -> new RejudgeTarget(rs.getLong("review_id"), rs.getString("source_url"),
                        rs.getLong("certification_id"), rs.getString("source_exam_code"),
                        rs.getObject("posted_at", LocalDate.class)),
                args);
    }

    @Override
    public int updateFromBody(long reviewId, LocalDate postedAt, ExtractedReview r, QualityResult q) {
        String dailyHoursText = r.dailyMinutes() == null ? null
                : String.valueOf(Math.round(r.dailyMinutes() / 6.0) / 10.0).replaceAll("\\.0$", "");
        return jdbc.update("""
                UPDATE PASS_REVIEWS SET exam_type = ?, major_type = ?, posted_at = COALESCE(posted_at, ?),
                       proof_yn = ?, prep_days = ?, total_hours = ?, daily_hours = ?, study_subjects = ?, evidence_text = ?,
                       review_status = ?, exclude_reason = ?, pass_yn = ?, daily_minutes = ?, exam_year = ?, round_no = ?,
                       study_method = ?
                 WHERE review_id = ?
                """,
                r.examType() == null ? null : r.examType().name(),
                r.majorType() == null ? null : r.majorType().name(),
                postedAt,
                r.proof() ? "Y" : "N",
                r.prepDays(), r.totalHours(), dailyHoursText, r.studySubjects(), r.evidenceText(),
                q.reviewStatus(), q.excludeReason(),
                r.passed() == null ? null : (r.passed() ? "Y" : "N"),
                r.dailyMinutes(), r.examYear(), r.roundNo(),
                r.studyMethod() == null ? null : r.studyMethod().name(),
                reviewId);
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
