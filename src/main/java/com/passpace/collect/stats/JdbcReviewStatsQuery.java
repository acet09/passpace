package com.passpace.collect.stats;

import com.passpace.common.stats.ReviewSample;
import com.passpace.common.stats.ReviewStatsQuery;
import com.passpace.common.stats.StatsCondition;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

/**
 * [용성 → 동건 제공] 공통 계약 ReviewStatsQuery 의 실제 구현.
 * PASS_REVIEWS 구조(확장 컬럼 포함)를 아는 용성이 SQL 을 책임진다.
 * 프로필이 fake 일 때는 꺼지고, 동건의 FakeReviewStatsQuery 가 대신 쓰인다 (Bean 중복 방지).
 */
@Component
@Profile("!fake")
public class JdbcReviewStatsQuery implements ReviewStatsQuery {

    private final JdbcTemplate jdbc;

    public JdbcReviewStatsQuery(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public List<ReviewSample> findSamples(StatsCondition c) {
        // 같은 작성자는 1표본(가장 최근 글), 작성일이 있는 글은 최근 3년만 (기획안 7.1.1 · 7.1.3)
        // author_hash 가 없는 행(더미·직접 입력)은 각각 1표본으로 본다
        StringBuilder sql = new StringBuilder("""
                SELECT pass_yn, daily_minutes, total_hours, prep_days, major_type, study_method,
                       study_subjects, evidence_text, source_url
                FROM (
                    SELECT p.*, ROW_NUMBER() OVER (
                               PARTITION BY COALESCE(p.author_hash, CONCAT('row-', p.review_id))
                               ORDER BY p.posted_at DESC, p.review_id DESC) AS author_rank
                    FROM PASS_REVIEWS p
                    WHERE p.certification_id = ? AND p.exam_type = ? AND p.review_status = 'VALID'
                      AND (p.posted_at IS NULL OR p.posted_at >= DATE_SUB(CURDATE(), INTERVAL 3 YEAR))
                ) t
                WHERE author_rank = 1
                  AND prep_days BETWEEN ? AND ?
                """);
        List<Object> args = new ArrayList<>(List.of(c.certificationId(), c.examType().name(), c.minPrepDays(), c.maxPrepDays()));
        if (c.majorType() != null) {
            sql.append(" AND major_type = ?");
            args.add(c.majorType().name());
        }
        return jdbc.query(sql.toString(), (rs, i) -> {
            String passYn = rs.getString("pass_yn");
            return new ReviewSample(
                    passYn == null ? null : "Y".equals(passYn),
                    rs.getObject("daily_minutes", Integer.class),
                    rs.getObject("total_hours", BigDecimal.class),
                    rs.getObject("prep_days", Integer.class),
                    rs.getString("major_type"),
                    rs.getString("study_method"),
                    rs.getString("study_subjects"),
                    rs.getString("evidence_text"),
                    rs.getString("source_url"));
        }, args.toArray());
    }
}
