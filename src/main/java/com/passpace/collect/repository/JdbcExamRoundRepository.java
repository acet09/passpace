package com.passpace.collect.repository;

import com.passpace.collect.dto.CollectDtos.ExamScheduleItem;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.Date;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

/** [용성] EXAM_ROUNDS JDBC 구현 */
@Repository
public class JdbcExamRoundRepository implements ExamRoundRepository {

    private final JdbcTemplate jdbc;

    public JdbcExamRoundRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public Optional<Long> findCertificationId(String examCode) {
        return jdbc.queryForList("SELECT certification_id FROM CERTIFICATIONS WHERE source_exam_code = ?", Long.class, examCode)
                .stream().findFirst();
    }

    @Override
    public Optional<StoredRound> find(long certificationId, int year, int roundNo, String examType) {
        List<StoredRound> rows = jdbc.query("""
                SELECT exam_round_id, reg_start_at, reg_end_at, exam_start_date, exam_end_date, result_date
                FROM EXAM_ROUNDS
                WHERE certification_id = ? AND exam_year = ? AND round_no = ? AND exam_type = ?
                """,
                (rs, i) -> new StoredRound(
                        rs.getLong("exam_round_id"),
                        toDate(rs.getObject("reg_start_at", LocalDateTime.class)),
                        toDate(rs.getObject("reg_end_at", LocalDateTime.class)),
                        rs.getObject("exam_start_date", LocalDate.class),
                        rs.getObject("exam_end_date", LocalDate.class),
                        rs.getObject("result_date", LocalDate.class)),
                certificationId, year, roundNo, examType);
        return rows.stream().findFirst();
    }

    @Override
    public void insert(long certificationId, long sourceId, String examCode, ExamScheduleItem it) {
        // exam_date(시험 기준일)는 ERD 에 exam_start_date 와 함께 있어 시작일과 같은 값으로 채운다
        jdbc.update("""
                INSERT INTO EXAM_ROUNDS (certification_id, source_id, source_exam_code, exam_year, round_no, exam_type,
                                         reg_start_at, reg_end_at, exam_date, exam_start_date, exam_end_date, result_date,
                                         last_synced_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
                """,
                certificationId, sourceId, examCode, it.examYear(), it.roundNo(), it.examType().name(),
                ts(it.regStart()), ts(it.regEnd()), d(it.examStart()), d(it.examStart()), d(it.examEnd()), d(it.resultDate()));
    }

    @Override
    public void update(long examRoundId, long sourceId, ExamScheduleItem it) {
        jdbc.update("""
                UPDATE EXAM_ROUNDS SET source_id = ?, reg_start_at = ?, reg_end_at = ?, exam_date = ?,
                       exam_start_date = ?, exam_end_date = ?, result_date = ?, last_synced_at = NOW()
                WHERE exam_round_id = ?
                """,
                sourceId, ts(it.regStart()), ts(it.regEnd()), d(it.examStart()), d(it.examStart()), d(it.examEnd()),
                d(it.resultDate()), examRoundId);
    }

    @Override
    public void touch(long examRoundId) {
        jdbc.update("UPDATE EXAM_ROUNDS SET last_synced_at = NOW() WHERE exam_round_id = ?", examRoundId);
    }

    @Override
    public void insertChangeLog(long examRoundId, Long syncLogId, StoredRound before, ExamScheduleItem after,
                                String changedFieldsJson) {
        jdbc.update("""
                INSERT INTO EXAM_SCHEDULE_CHANGE_LOGS (exam_round_id, sync_log_id, old_exam_start_date, old_exam_end_date,
                       new_exam_start_date, new_exam_end_date, changed_fields, change_reason, detected_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())
                """,
                examRoundId, syncLogId, d(before.examStart()), d(before.examEnd()),
                d(after.examStart()), d(after.examEnd()), changedFieldsJson, "공공데이터 재수집 시 값 변경 감지");
    }

    private static LocalDate toDate(LocalDateTime t) {
        return t == null ? null : t.toLocalDate();
    }

    private static Date d(LocalDate v) {
        return v == null ? null : Date.valueOf(v);
    }

    private static Timestamp ts(LocalDate v) {
        return v == null ? null : Timestamp.valueOf(v.atStartOfDay());
    }
}
