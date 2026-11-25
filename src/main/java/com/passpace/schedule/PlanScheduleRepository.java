package com.passpace.schedule;

import com.passpace.error.ErrorCode;
import com.passpace.schedule.PlanScheduleDtos.ScheduleException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.Optional;

@Repository
public class PlanScheduleRepository {
    private final JdbcTemplate jdbc;

    public PlanScheduleRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public record Entry(int version, LocalDate start, LocalDate end, LocalDate date, int minutes) {}
    public record PlanWindow(int version, LocalDate start, LocalDate end, LocalDate firstTask, LocalDate lastTask) {}

    public Optional<PlanWindow> lockPeriod(long userId, long planId) {
        return jdbc.query("""
                SELECT p.version_no, p.start_date, p.end_date,
                       (SELECT MIN(t.scheduled_date) FROM STUDY_PLAN_DETAILS t
                        WHERE t.plan_id = p.plan_id AND t.user_id = p.user_id) AS first_task,
                       (SELECT MAX(t.scheduled_date) FROM STUDY_PLAN_DETAILS t
                        WHERE t.plan_id = p.plan_id AND t.user_id = p.user_id) AS last_task
                FROM STUDY_PLANS p
                WHERE p.user_id = ? AND p.plan_id = ?
                  AND p.plan_type = 'CHATBOT' AND p.status IN ('ACTIVE', 'REPLACED')
                FOR UPDATE
                """, (rs, index) -> new PlanWindow(rs.getInt("version_no"),
                rs.getObject("start_date", LocalDate.class), rs.getObject("end_date", LocalDate.class),
                rs.getObject("first_task", LocalDate.class), rs.getObject("last_task", LocalDate.class)),
                userId, planId).stream().findFirst();
    }

    public int updatePeriod(long userId, long planId, LocalDate start, LocalDate end, int version) {
        int rows = jdbc.update("""
                UPDATE STUDY_PLANS SET start_date = ?, end_date = ?, version_no = version_no + 1
                WHERE user_id = ? AND plan_id = ? AND version_no = ?
                """, start, end, userId, planId, version);
        if (rows != 1) {
            throw new ScheduleException(ErrorCode.DATA_INTEGRITY_VIOLATION,
                    "계획이 바뀌었어요. 최신 일정을 확인해 주세요.");
        }
        return Math.addExact(version, 1);
    }

    public Optional<Entry> lockEntry(long userId, long planId, long taskId) {
        return jdbc.query("""
                SELECT p.version_no, p.start_date, p.end_date, t.scheduled_date, t.estimated_minutes
                FROM STUDY_PLANS p
                JOIN STUDY_PLAN_DETAILS t ON t.plan_id = p.plan_id AND t.user_id = p.user_id
                WHERE p.user_id = ? AND p.plan_id = ? AND t.task_id = ?
                  AND p.plan_type = 'CHATBOT' AND p.status IN ('ACTIVE', 'REPLACED')
                FOR UPDATE
                """, (rs, index) -> new Entry(rs.getInt("version_no"),
                rs.getObject("start_date", LocalDate.class), rs.getObject("end_date", LocalDate.class),
                rs.getObject("scheduled_date", LocalDate.class), rs.getInt("estimated_minutes")),
                userId, planId, taskId).stream().findFirst();
    }

    public long savedMinutes(long userId, long taskId, LocalDate date) {
        return jdbc.queryForObject("""
                SELECT COALESCE(SUM(actual_minutes), 0) FROM STUDY_SESSIONS
                WHERE user_id = ? AND task_id = ? AND study_date = ?
                """, Long.class, userId, taskId, date);
    }

    public long otherPlannedMinutes(long userId, long planId, long taskId, LocalDate date) {
        return jdbc.queryForObject("""
                SELECT COALESCE(SUM(estimated_minutes), 0) FROM STUDY_PLAN_DETAILS
                WHERE user_id = ? AND plan_id = ? AND task_id <> ? AND scheduled_date = ?
                """, Long.class, userId, planId, taskId, date);
    }

    public int update(long userId, long planId, long taskId, LocalDate originalDate,
                      LocalDate date, int minutes, int expectedVersion) {
        int detailRows = jdbc.update("""
                UPDATE STUDY_PLAN_DETAILS
                SET carried_from_date = CASE WHEN scheduled_date <> ?
                        THEN COALESCE(carried_from_date, scheduled_date) ELSE carried_from_date END,
                    scheduled_date = ?, estimated_minutes = ?
                WHERE user_id = ? AND plan_id = ? AND task_id = ? AND scheduled_date = ?
                """, date, date, minutes, userId, planId, taskId, originalDate);
        int planRows = jdbc.update("""
                UPDATE STUDY_PLANS SET version_no = version_no + 1
                WHERE user_id = ? AND plan_id = ? AND version_no = ?
                """, userId, planId, expectedVersion);
        if (detailRows != 1 || planRows != 1) {
            throw new ScheduleException(ErrorCode.DATA_INTEGRITY_VIOLATION,
                    "계획이 바뀌었어요. 최신 일정을 확인해 주세요.");
        }
        return Math.addExact(expectedVersion, 1);
    }
}
