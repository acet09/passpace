package com.passpace.repository;

import com.passpace.service.SubjectStudyExtractor.Mention;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * [용성 · 11-16] REVIEW_SUBJECT_MENTIONS (db/10) JDBC 구현 — 후기별 과목 언급 저장.
 *
 * 안전장치
 *  - 이 테이블이 없는 DB(아직 db/10 을 실행하지 않은 팀원 PC)에서도 후기 수집은 그대로 동작한다.
 *    저장에 실패하면 경고 로그를 한 번만 남기고 0건으로 넘어간다 (후기 저장에는 영향 없음)
 *  - 후기를 지우면 이 테이블의 줄은 DB 가 자동으로 지운다 (ON DELETE CASCADE)
 */
@Repository
public class JdbcReviewSubjectMentionRepository {

    private static final Logger log = LoggerFactory.getLogger(JdbcReviewSubjectMentionRepository.class);

    private final JdbcTemplate jdbc;
    private final AtomicBoolean warned = new AtomicBoolean(false);

    public JdbcReviewSubjectMentionRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** db/10 을 실행해 테이블이 있는지 */
    public boolean tableExists() {
        try {
            Integer n = jdbc.queryForObject("""
                    SELECT COUNT(*) FROM information_schema.TABLES
                    WHERE TABLE_SCHEMA = DATABASE() AND UPPER(TABLE_NAME) = 'REVIEW_SUBJECT_MENTIONS'
                    """, Integer.class);
            return n != null && n > 0;
        } catch (DataAccessException e) {
            return false;
        }
    }

    /**
     * 방금 저장한 후기(source_url 로 찾음)의 과목 언급을 저장한다.
     * PASS_REVIEWS.insert 가 review_id 를 돌려주지 않아서(기존 시그니처 유지) 주소로 찾는다.
     *
     * @return 저장한 줄 수 (테이블이 없거나 실패하면 0)
     */
    public int saveForUrl(String sourceUrl, long certificationId, List<Mention> mentions) {
        if (mentions == null || mentions.isEmpty()) return 0;
        try {
            List<Long> ids = jdbc.queryForList(
                    "SELECT review_id FROM PASS_REVIEWS WHERE source_url = ? ORDER BY review_id DESC LIMIT 1",
                    Long.class, sourceUrl);
            if (ids.isEmpty()) return 0;
            return saveForReview(ids.get(0), certificationId, mentions);
        } catch (DataAccessException e) {
            warnOnce(e);
            return 0;
        }
    }

    /** 후기 번호를 알 때 (기존 후기 채우기). 같은 후기·과목·종류가 이미 있으면 건너뜀 */
    public int saveForReview(long reviewId, long certificationId, List<Mention> mentions) {
        if (mentions == null || mentions.isEmpty()) return 0;
        try {
            int saved = 0;
            for (Mention m : mentions) {
                // 같은 자격증의 과목만 저장한다 (예: SQLD 후기의 "프로그래밍 언어"는 정처기 과목이라 버림)
                // 예외: 옛 정처기 과목 "소프트웨어 설계"는 2027 기준에 없어 번호 없이(NULL) 저장
                saved += jdbc.update("""
                        INSERT IGNORE INTO REVIEW_SUBJECT_MENTIONS
                          (review_id, certification_subject_id, subject_name, mention_type,
                           study_hours, hours_ratio, estimated_yn, evidence_text)
                        SELECT ?, (SELECT MIN(s.certification_subject_id) FROM CERTIFICATION_SUBJECTS s
                                   WHERE s.certification_id = ? AND s.subject_name = ?),
                               ?, ?, ?, ?, ?, ?
                        FROM DUAL
                        WHERE EXISTS (SELECT 1 FROM CERTIFICATION_SUBJECTS s
                                      WHERE s.certification_id = ? AND s.subject_name = ?)
                           OR (? = '소프트웨어 설계' AND EXISTS (SELECT 1 FROM CERTIFICATION_SUBJECTS s
                                      WHERE s.certification_id = ? AND s.subject_name = '소프트웨어 개발'))
                        """,
                        reviewId, certificationId, m.subjectName(),
                        m.subjectName(), m.type().name(),
                        m.hours(), m.ratioPercent(), m.estimated() ? "Y" : "N", m.evidence(),
                        certificationId, m.subjectName(), m.subjectName(), certificationId);
            }
            return saved;
        } catch (DataAccessException e) {
            warnOnce(e);
            return 0;
        }
    }

    private void warnOnce(DataAccessException e) {
        if (warned.compareAndSet(false, true)) {
            log.warn("과목 언급 저장 건너뜀 (db/10_review_subject_mentions.sql 실행 여부 확인): {}", e.getMostSpecificCause().getMessage());
        }
    }
}
