package com.passpace.study;

import com.passpace.study.StudyDtos.DayTotal;
import com.passpace.study.StudyDtos.PlanTask;
import com.passpace.study.StudyDtos.SessionRow;
import com.passpace.study.StudyDtos.UserState;
import com.passpace.study.StudyDtos.PlanTaskChoice;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.stereotype.Repository;

import java.sql.PreparedStatement;
import java.sql.Statement;
import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.ArrayList;
import java.util.Optional;

/** [한결] 공부기록 JDBC 저장소. SQL에는 인증된 사용자 ID 조건과 바인딩을 사용한다. */
@Repository
public class JdbcStudyRepository implements StudyRepository {
    private final JdbcTemplate jdbc;

    public JdbcStudyRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public Optional<UserState> findUser(long userId, boolean lock) {
        String sql = "SELECT major_type FROM USERS WHERE user_id = ?" + (lock ? " FOR UPDATE" : "");
        return jdbc.query(sql, (rs, n) -> new UserState(rs.getString("major_type")), userId)
                .stream().findFirst();
    }

    @Override
    public Optional<PlanTask> findOwnedTaskForUpdate(long userId, long taskId) {
        return jdbc.query("""
                SELECT t.task_id, t.plan_id, t.certification_subject_id, t.subject_name,
                       p.version_no, p.status
                FROM STUDY_PLAN_DETAILS t
                JOIN STUDY_PLANS p ON p.plan_id = t.plan_id AND p.user_id = ?
                WHERE t.task_id = ? AND t.user_id = ?
                FOR UPDATE
                """, (rs, n) -> new PlanTask(rs.getLong("task_id"), rs.getLong("plan_id"),
                rs.getObject("certification_subject_id", Long.class), rs.getString("subject_name"),
                rs.getObject("version_no", Integer.class), rs.getString("status")),
                userId, taskId, userId).stream().findFirst();
    }

    @Override
    public long insert(long userId, Long taskId, LocalDate studyDate, int durationMinutes) {
        var keys = new GeneratedKeyHolder();
        jdbc.update(connection -> {
            PreparedStatement ps = connection.prepareStatement("""
                    INSERT INTO STUDY_SESSIONS
                        (user_id, task_id, study_date, actual_minutes, input_method)
                    VALUES (?, ?, ?, ?, 'MANUAL')
                    """, Statement.RETURN_GENERATED_KEYS);
            ps.setLong(1, userId);
            if (taskId == null) ps.setNull(2, Types.BIGINT);
            else ps.setLong(2, taskId);
            ps.setObject(3, studyDate);
            ps.setInt(4, durationMinutes);
            return ps;
        }, keys);
        Number id = keys.getKey();
        if (id == null) throw new IllegalStateException("학습기록 저장 결과를 확인하지 못했습니다.");
        return id.longValue();
    }

    @Override
    public Optional<SessionRow> findOwnedSessionForUpdate(long userId, long sessionId) {
        return jdbc.query("""
                SELECT s.session_id, s.study_date, s.actual_minutes, s.task_id, s.input_method,
                       p.plan_id, t.certification_subject_id, t.subject_name,
                       CASE WHEN s.task_id IS NOT NULL AND
                            (t.task_id IS NULL OR p.plan_id IS NULL) THEN 1 ELSE 0 END AS invalid_link
                FROM STUDY_SESSIONS s
                LEFT JOIN STUDY_PLAN_DETAILS t ON t.task_id = s.task_id AND t.user_id = s.user_id
                LEFT JOIN STUDY_PLANS p ON p.plan_id = t.plan_id AND p.user_id = s.user_id
                WHERE s.user_id = ? AND s.session_id = ?
                FOR UPDATE
                """, (rs, n) -> new SessionRow(rs.getLong("session_id"),
                rs.getObject("study_date", LocalDate.class), rs.getObject("actual_minutes", Integer.class),
                rs.getObject("task_id", Long.class), rs.getObject("plan_id", Long.class),
                rs.getObject("certification_subject_id", Long.class), rs.getString("subject_name"),
                rs.getString("input_method"), rs.getBoolean("invalid_link")), userId, sessionId)
                .stream().findFirst();
    }

    @Override
    public int updateOwnedSession(long userId, long sessionId, LocalDate date, int minutes,
                                  LocalDate expectedDate, int expectedMinutes, Long taskId, Long expectedTaskId) {
        return jdbc.update("""
                UPDATE STUDY_SESSIONS SET study_date = ?, actual_minutes = ?, task_id = ?
                WHERE user_id = ? AND session_id = ? AND input_method = 'MANUAL'
                  AND study_date = ? AND actual_minutes = ? AND task_id <=> ?
                """, ps -> {
            ps.setObject(1, date);
            ps.setInt(2, minutes);
            if (taskId == null) ps.setNull(3, Types.BIGINT); else ps.setLong(3, taskId);
            ps.setLong(4, userId);
            ps.setLong(5, sessionId);
            ps.setObject(6, expectedDate);
            ps.setInt(7, expectedMinutes);
            if (expectedTaskId == null) ps.setNull(8, Types.BIGINT); else ps.setLong(8, expectedTaskId);
        });
    }

    @Override
    public int deleteOwnedSession(long userId, long sessionId, LocalDate expectedDate, int expectedMinutes,
                                  Long expectedTaskId) {
        return jdbc.update("""
                DELETE FROM STUDY_SESSIONS WHERE user_id = ? AND session_id = ?
                  AND input_method = 'MANUAL' AND study_date = ? AND actual_minutes = ? AND task_id <=> ?
                """, ps -> {
            ps.setLong(1, userId); ps.setLong(2, sessionId);
            ps.setObject(3, expectedDate); ps.setInt(4, expectedMinutes);
            if (expectedTaskId == null) ps.setNull(5, Types.BIGINT); else ps.setLong(5, expectedTaskId);
        });
    }

    @Override
    public List<PlanTaskChoice> findOwnedPlanTasks(long userId, LocalDate date, boolean includeReplaced,
                                                int limit, long offset) {
        String sql = """
                SELECT t.task_id, p.plan_id, p.plan_name, p.version_no, t.certification_subject_id,
                       t.subject_name, t.study_category, t.scheduled_date, p.status
                FROM STUDY_PLAN_DETAILS t JOIN STUDY_PLANS p ON p.plan_id = t.plan_id AND p.user_id = t.user_id
                WHERE t.user_id = ? AND p.user_id = ? AND p.version_no > 0 AND
                """ + (includeReplaced ? "p.status IN ('ACTIVE','REPLACED')" : "p.status = 'ACTIVE'") +
                (date == null ? "" : " AND t.scheduled_date = ?") +
                " ORDER BY t.scheduled_date IS NULL, t.scheduled_date, t.task_id LIMIT ? OFFSET ?";
        List<Object> args = new ArrayList<>(List.of(userId, userId));
        if (date != null) args.add(date);
        args.add(limit); args.add(offset);
        return jdbc.query(sql, (rs, n) -> new PlanTaskChoice(rs.getLong("task_id"), rs.getLong("plan_id"),
                rs.getString("plan_name"), rs.getInt("version_no"),
                rs.getObject("certification_subject_id", Long.class), rs.getString("subject_name"),
                rs.getString("study_category"), rs.getObject("scheduled_date", LocalDate.class),
                rs.getString("status")), args.toArray());
    }

    @Override
    public List<SessionRow> findSessions(long userId, LocalDate startDate, LocalDate endDate,
                                         int limit, long offset) {
        return jdbc.query("""
                SELECT s.session_id, s.study_date, s.actual_minutes, s.task_id, s.input_method,
                       p.plan_id, t.certification_subject_id, t.subject_name,
                       CASE WHEN s.task_id IS NOT NULL AND
                            (t.task_id IS NULL OR p.plan_id IS NULL) THEN 1 ELSE 0 END AS invalid_link
                FROM STUDY_SESSIONS s
                LEFT JOIN STUDY_PLAN_DETAILS t ON t.task_id = s.task_id AND t.user_id = s.user_id
                LEFT JOIN STUDY_PLANS p ON p.plan_id = t.plan_id AND p.user_id = s.user_id
                WHERE s.user_id = ? AND s.study_date >= ? AND s.study_date <= ?
                ORDER BY s.study_date DESC, s.session_id DESC
                LIMIT ? OFFSET ?
                """, (rs, n) -> new SessionRow(rs.getLong("session_id"),
                rs.getObject("study_date", LocalDate.class), rs.getObject("actual_minutes", Integer.class),
                rs.getObject("task_id", Long.class), rs.getObject("plan_id", Long.class),
                rs.getObject("certification_subject_id", Long.class), rs.getString("subject_name"),
                rs.getString("input_method"), rs.getBoolean("invalid_link")),
                userId, startDate, endDate, limit, offset);
    }

    @Override
    public List<DayTotal> findDailyTotals(long userId, LocalDate startDate, LocalDate endDate) {
        return jdbc.query("""
                SELECT s.study_date, COALESCE(SUM(s.actual_minutes), 0) AS duration_minutes,
                       SUM(CASE WHEN s.actual_minutes IS NULL OR s.actual_minutes <= 0 OR
                                     s.actual_minutes > 1440 OR
                                     (s.task_id IS NOT NULL AND (t.task_id IS NULL OR p.plan_id IS NULL))
                                THEN 1 ELSE 0 END) AS invalid_records
                FROM STUDY_SESSIONS s
                LEFT JOIN STUDY_PLAN_DETAILS t ON t.task_id = s.task_id AND t.user_id = s.user_id
                LEFT JOIN STUDY_PLANS p ON p.plan_id = t.plan_id AND p.user_id = s.user_id
                WHERE s.user_id = ? AND s.study_date >= ? AND s.study_date <= ?
                GROUP BY s.study_date
                ORDER BY s.study_date
                """, (rs, n) -> new DayTotal(rs.getObject("study_date", LocalDate.class),
                rs.getLong("duration_minutes"), rs.getLong("invalid_records")),
                userId, startDate, endDate);
    }
}
