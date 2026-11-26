package com.passpace.schedule;

import com.passpace.error.ErrorCode;
import com.passpace.schedule.PlanScheduleDtos.ScheduleException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

/** [한결] 전체 일정 수정에서 쓰는 계획과 기록 보호 조회. */
@Repository
public class WholePlanRepository {
    private final JdbcTemplate jdbc;

    public WholePlanRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public record Plan(String name, int version, LocalDate start, LocalDate end, String weekdayJson) {}
    public record Topic(Long subjectId, String exam, String name, Long goalId) {}
    public record Item(long id, Topic topic, LocalDate date, int minutes, boolean recorded, boolean moved) {
        boolean protectedOn(LocalDate today) {
            return recorded || moved || date == null || date.isBefore(today) || minutes < 1
                    || topic.name() == null || topic.name().isBlank();
        }
    }
    public record Placement(Topic topic, LocalDate date, int minutes) {}

    public Optional<Plan> plan(long userId, long planId, boolean lock) {
        return jdbc.query("""
                SELECT plan_name, version_no, start_date, end_date, weekday_minutes
                FROM STUDY_PLANS
                WHERE user_id = ? AND plan_id = ? AND plan_type = 'CHATBOT' AND status = 'ACTIVE'
                """ + (lock ? " FOR UPDATE" : ""),
                (rs, index) -> new Plan(rs.getString("plan_name"), rs.getInt("version_no"),
                        rs.getObject("start_date", LocalDate.class), rs.getObject("end_date", LocalDate.class),
                        rs.getString("weekday_minutes")), userId, planId).stream().findFirst();
    }

    public List<Item> items(long userId, long planId) {
        return jdbc.query("""
                SELECT t.task_id, t.certification_subject_id, t.study_category, t.subject_name, t.goal_id,
                       t.scheduled_date, t.estimated_minutes, t.carried_from_date,
                       EXISTS (SELECT 1 FROM STUDY_SESSIONS s
                               WHERE s.task_id = t.task_id AND s.user_id = t.user_id) AS recorded
                FROM STUDY_PLAN_DETAILS t
                WHERE t.user_id = ? AND t.plan_id = ?
                ORDER BY t.scheduled_date, t.task_id
                """, (rs, index) -> new Item(rs.getLong("task_id"),
                        new Topic(rs.getObject("certification_subject_id", Long.class),
                                rs.getString("study_category"), rs.getString("subject_name"),
                                rs.getObject("goal_id", Long.class)),
                        rs.getObject("scheduled_date", LocalDate.class), rs.getInt("estimated_minutes"),
                        rs.getBoolean("recorded"), rs.getObject("carried_from_date") != null), userId, planId);
    }

    public void apply(long userId, long planId, Plan original, String name, LocalDate start, LocalDate end,
                      String weekdayJson, List<Item> removed, List<Placement> added) {
        int changed = jdbc.update("""
                UPDATE STUDY_PLANS SET plan_name = ?, start_date = ?, end_date = ?,
                                       weekday_minutes = ?, version_no = version_no + 1
                WHERE user_id = ? AND plan_id = ? AND version_no = ? AND status = 'ACTIVE'
                """, name, start, end, weekdayJson, userId, planId, original.version());
        if (changed != 1) throw conflict();

        for (var item : removed) {
            int deleted = jdbc.update("""
                    DELETE FROM STUDY_PLAN_DETAILS
                    WHERE user_id = ? AND plan_id = ? AND task_id = ? AND scheduled_date = ?
                      AND carried_from_date IS NULL
                      AND NOT EXISTS (SELECT 1 FROM STUDY_SESSIONS s
                                      WHERE s.task_id = ? AND s.user_id = ?)
                    """, userId, planId, item.id(), item.date(), item.id(), userId);
            if (deleted != 1) throw conflict();
        }
        if (!added.isEmpty()) {
            jdbc.batchUpdate("""
                    INSERT INTO STUDY_PLAN_DETAILS (user_id, plan_id, goal_id, certification_subject_id,
                        task_title, study_category, subject_name, scheduled_date, estimated_minutes, created_by)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'CHATBOT')
                    """, added.stream().map(item -> {
                var topic = item.topic();
                String title = topic.exam() == null || topic.exam().isBlank()
                        ? topic.name() : topic.exam() + " · " + topic.name();
                return new Object[]{userId, planId, topic.goalId(), topic.subjectId(),
                        title.substring(0, Math.min(title.length(), 200)), topic.exam(), topic.name(),
                        item.date(), item.minutes()};
            }).toList());
        }
    }

    private static ScheduleException conflict() {
        return new ScheduleException(ErrorCode.DATA_INTEGRITY_VIOLATION,
                "일정이나 학습기록이 바뀌었어요. 다시 확인해 주세요.");
    }
}
