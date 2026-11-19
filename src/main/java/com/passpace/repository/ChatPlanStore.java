package com.passpace.repository;

import com.passpace.service.MultiGoalPlanCalculator.Allocation;
import com.passpace.service.MultiGoalPlanCalculator.DaySchedule;
import com.passpace.service.MultiGoalPlanCalculator.PlanResponse;
import com.passpace.service.PlanReplanner.PlannedTask;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * [동건] 챗봇이 계산한 계획을 마이페이지에서 볼 수 있게 넣어 두는 최소 저장소.
 *
 * 기존 ERD 테이블만 쓴다 (스키마 변경 없음).
 *   STUDY_PLANS         계획 1건  (plan_type = 'CHATBOT', 사용자당 status = 'ACTIVE' 는 1건)
 *   STUDY_PLAN_DETAILS  날짜·과목별 할 일 (created_by = 'CHATBOT')
 * 저장한 계획은 지우기 전까지 목록에 남는다. 그중 "지금 쓰는 계획" 하나만 ACTIVE 이고 나머지는 REPLACED(보관)이다.
 *   - 바로 사용으로 저장하면 쓰던 계획은 REPLACED 로 바뀌고 새 계획이 ACTIVE 가 된다
 *   - 목록에만 추가하면 새 계획이 REPLACED 로 들어가고 쓰던 계획은 그대로다
 *   - 상태 값은 학습기록(한결) 쪽이 읽는 ACTIVE·REPLACED 두 가지만 쓴다
 * 학습 계획·통계 담당 영역이 정식으로 만들어지면 이 클래스는 그쪽 저장 방식으로 교체한다.
 */
@Repository
public class ChatPlanStore {

    public static final String PLAN_TYPE = "CHATBOT";

    /** 마이페이지 표시용 할 일 한 줄 */
    public record Task(LocalDate date, String certificationName, String subjectName, int minutes) {
    }

    /** 저장된 챗봇 계획 */
    public record SavedPlan(long planId, String planName, int versionNo, LocalDate startDate, LocalDate endDate,
                            List<Task> tasks) {
    }

    /** 계획 목록 한 줄 (할 일은 빼고 요약만) */
    public record PlanSummary(long planId, String planName, int versionNo, LocalDate startDate, LocalDate endDate,
                              boolean active, int days, int totalMinutes) {
    }

    private final JdbcTemplate jdbc;

    public ChatPlanStore(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** 새 계획을 저장하고 바로 사용한다 (쓰던 계획은 목록에 보관). */
    @Transactional
    public long replace(long userId, PlanResponse plan, Map<String, Long> subjectIds) {
        return save(userId, plan, subjectIds, true);
    }

    /**
     * @param subjectIds "목표키|과목명" → CERTIFICATION_SUBJECTS ID (모르면 없어도 됨)
     * @param activate   true 면 바로 사용(쓰던 계획은 보관), false 면 목록에만 추가
     * @return 새 계획 ID
     */
    @Transactional
    public long save(long userId, PlanResponse plan, Map<String, Long> subjectIds, boolean activate) {
        return save(userId, plan, subjectIds, activate, plan.weekdayMinutes());
    }

    /**
     * @param dayCaps 요일(1=월 … 7=일) → 그날 쓸 수 있는 시간(분). weekday_minutes 칸에 남겨 두었다가
     *                계획이 밀려 일정을 다시 짤 때 같은 요일·같은 시간으로 계산한다. 모르면 null.
     */
    @Transactional
    public long save(long userId, PlanResponse plan, Map<String, Long> subjectIds, boolean activate,
                     Map<Integer, Integer> dayCaps) {
        if (plan.days().isEmpty()) throw new IllegalArgumentException("저장할 날짜별 계획이 없습니다.");
        if (activate)
            jdbc.update("UPDATE STUDY_PLANS SET status = 'REPLACED' WHERE user_id = ? AND plan_type = ? AND status = 'ACTIVE'",
                    userId, PLAN_TYPE);
        Integer version = jdbc.queryForObject(
                "SELECT COALESCE(MAX(version_no), 0) + 1 FROM STUDY_PLANS WHERE user_id = ? AND plan_type = ?",
                Integer.class, userId, PLAN_TYPE);
        LocalDate start = plan.days().get(0).date();
        LocalDate end = plan.days().get(plan.days().size() - 1).date();
        String name = "챗봇 학습계획 (" + String.join(" + ",
                plan.goals().stream().map(g -> g.certificationName()).toList()) + ", "
                // 요일마다 시간이 같으면 "하루 N분", 다르면 "월 60분·토 240분"
                + (plan.weekdayMinutes() == null || new java.util.HashSet<>(plan.weekdayMinutes().values()).size() == 1
                ? "하루 " + plan.dailyMinutes() + "분"
                : com.passpace.service.MultiGoalPlanCalculator.weekdayMinutesLabel(plan.weekdayMinutes())) + ")";
        // 요일별 가능시간을 ERD 의 weekday_minutes 칸에 {"1":60,"6":240} 모양으로 남긴다.
        String weekdayJson = dayCaps == null || dayCaps.isEmpty() ? null : "{" + String.join(",",
                new java.util.TreeMap<>(dayCaps).entrySet().stream()
                        .map(e -> "\"" + e.getKey() + "\":" + e.getValue()).toList()) + "}";
        String planName = name.length() <= 200 ? name : name.substring(0, 200);

        KeyHolder key = new GeneratedKeyHolder();
        jdbc.update(con -> {
            PreparedStatement ps = con.prepareStatement("""
                    INSERT INTO STUDY_PLANS (user_id, plan_name, plan_type, version_no, start_date, end_date, status,
                                             weekday_minutes)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, Statement.RETURN_GENERATED_KEYS);
            ps.setLong(1, userId);
            ps.setString(2, planName);
            ps.setString(3, PLAN_TYPE);
            ps.setInt(4, version == null ? 1 : version);
            ps.setDate(5, Date.valueOf(start));
            ps.setDate(6, Date.valueOf(end));
            ps.setString(7, activate ? "ACTIVE" : "REPLACED");
            ps.setString(8, weekdayJson);
            return ps;
        }, key);
        long planId = key.getKey().longValue();

        List<Object[]> rows = new ArrayList<>();
        for (DaySchedule day : plan.days()) {
            for (Allocation a : day.allocations()) {
                rows.add(new Object[]{userId, planId, subjectIds.get(a.goalKey() + "|" + a.subjectName()),
                        a.certificationName() + " · " + a.subjectName(), a.certificationName(), a.subjectName(),
                        Date.valueOf(day.date()), a.minutes()});
            }
        }
        // study_category 에는 자격증 이름을 넣어 둔다 (주별·월별로 자격증마다 묶어 보기 위한 값)
        jdbc.batchUpdate("""
                INSERT INTO STUDY_PLAN_DETAILS (user_id, plan_id, certification_subject_id, task_title, study_category,
                       subject_name, scheduled_date, estimated_minutes, created_by)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'CHATBOT')
                """, rows);
        return planId;
    }

    /** 지금 쓰는 챗봇 계획 (없으면 null) */
    public SavedPlan findActive(long userId) {
        return load(userId, "status = 'ACTIVE'");
    }

    /** 목록의 계획 한 건을 할 일까지 (없거나 남의 계획이면 null) */
    public SavedPlan find(long userId, long planId) {
        return load(userId, "status IN ('ACTIVE', 'REPLACED') AND plan_id = " + planId);
    }

    /** 저장한 계획 목록: 지금 쓰는 계획이 맨 위, 나머지는 최근에 저장한 순서 */
    public List<PlanSummary> list(long userId) {
        return jdbc.query("""
                SELECT p.plan_id, p.plan_name, p.version_no, p.start_date, p.end_date, p.status,
                       COUNT(DISTINCT t.scheduled_date) AS days, COALESCE(SUM(t.estimated_minutes), 0) AS minutes
                FROM STUDY_PLANS p
                LEFT JOIN STUDY_PLAN_DETAILS t ON t.plan_id = p.plan_id AND t.user_id = p.user_id
                WHERE p.user_id = ? AND p.plan_type = ? AND p.status IN ('ACTIVE', 'REPLACED')
                GROUP BY p.plan_id, p.plan_name, p.version_no, p.start_date, p.end_date, p.status
                ORDER BY CASE WHEN p.status = 'ACTIVE' THEN 0 ELSE 1 END, p.plan_id DESC
                """, (rs, n) -> new PlanSummary(rs.getLong("plan_id"), rs.getString("plan_name"),
                rs.getInt("version_no"), rs.getObject("start_date", LocalDate.class),
                rs.getObject("end_date", LocalDate.class), "ACTIVE".equals(rs.getString("status")),
                rs.getInt("days"), rs.getInt("minutes")), userId, PLAN_TYPE);
    }

    /** 목록의 계획을 지금 쓰는 계획으로 바꾼다. 쓰던 계획은 목록에 보관된다. */
    @Transactional
    public void activate(long userId, long planId) {
        requireOwned(userId, planId);
        jdbc.update("UPDATE STUDY_PLANS SET status = 'REPLACED' WHERE user_id = ? AND plan_type = ? AND status = 'ACTIVE'",
                userId, PLAN_TYPE);
        jdbc.update("UPDATE STUDY_PLANS SET status = 'ACTIVE' WHERE plan_id = ? AND user_id = ? AND plan_type = ?",
                planId, userId, PLAN_TYPE);
    }

    /**
     * 목록에서 계획을 지운다 (할 일까지 함께).
     * 학습기록이 이 계획의 할 일에 연결돼 있으면 기록이 끊기므로 지우지 않는다.
     */
    @Transactional
    public void delete(long userId, long planId) {
        requireOwned(userId, planId);
        Integer linked = jdbc.queryForObject("""
                SELECT COUNT(*) FROM STUDY_SESSIONS s
                JOIN STUDY_PLAN_DETAILS t ON t.task_id = s.task_id
                WHERE t.plan_id = ? AND t.user_id = ?
                """, Integer.class, planId, userId);
        if (linked != null && linked > 0)
            throw new IllegalArgumentException("이 계획에 연결된 학습기록이 " + linked + "건 있어 삭제할 수 없습니다.");
        // 이 계획에 대한 재편성 추천 기록도 함께 지운다 (남아 있으면 계획을 지울 수 없다).
        jdbc.update("DELETE FROM AI_PLAN_PROPOSALS WHERE user_id = ? AND (current_plan_id = ? OR proposed_plan_id = ?)",
                userId, planId, planId);
        jdbc.update("DELETE FROM STUDY_PLAN_DETAILS WHERE plan_id = ? AND user_id = ?", planId, userId);
        jdbc.update("DELETE FROM STUDY_PLANS WHERE plan_id = ? AND user_id = ? AND plan_type = ?",
                planId, userId, PLAN_TYPE);
    }

    // ---------------------------------------------------------------------
    // 재편성 추천: 지금 쓰는 계획과 학습기록을 읽고, 추천·수락·거절을 AI_PLAN_PROPOSALS 에 남긴다
    // ---------------------------------------------------------------------

    /** 재편성 계산에 쓰는 지금 계획: 요일별 가능시간(없을 수 있음)과 과목 ID 가 붙은 할 일 */
    public record ReplanSource(long planId, String planName, LocalDate startDate, String weekdayMinutesJson,
                               List<PlannedTask> tasks) {
    }

    public static final String REASON_BEHIND = "BEHIND_SCHEDULE";

    /** 지금 쓰는 계획 (없으면 null) */
    public ReplanSource findActiveForReplan(long userId) {
        List<ReplanSource> plans = jdbc.query("""
                SELECT plan_id, plan_name, start_date, weekday_minutes FROM STUDY_PLANS
                WHERE user_id = ? AND plan_type = ? AND status = 'ACTIVE' ORDER BY plan_id DESC LIMIT 1
                """, (rs, n) -> new ReplanSource(rs.getLong("plan_id"), rs.getString("plan_name"),
                rs.getObject("start_date", LocalDate.class), rs.getString("weekday_minutes"), List.of()),
                userId, PLAN_TYPE);
        if (plans.isEmpty()) return null;
        ReplanSource p = plans.get(0);
        List<PlannedTask> tasks = jdbc.query("""
                SELECT scheduled_date, study_category, subject_name, certification_subject_id, estimated_minutes
                FROM STUDY_PLAN_DETAILS
                WHERE plan_id = ? AND user_id = ? AND scheduled_date IS NOT NULL AND estimated_minutes > 0
                ORDER BY scheduled_date, task_id
                """, (rs, n) -> new PlannedTask(rs.getObject("scheduled_date", LocalDate.class),
                rs.getString("study_category"), rs.getString("subject_name"),
                rs.getObject("certification_subject_id", Long.class), rs.getInt("estimated_minutes")),
                p.planId(), userId);
        return new ReplanSource(p.planId(), p.planName(), p.startDate(), p.weekdayMinutesJson(), tasks);
    }

    /** from 부터 beforeExclusive 전날까지 기록한 공부 시간(분). 할 일에 연결하지 않은 기록도 센다. */
    public int doneMinutes(long userId, LocalDate from, LocalDate beforeExclusive) {
        Integer sum = jdbc.queryForObject("""
                SELECT COALESCE(SUM(actual_minutes), 0) FROM STUDY_SESSIONS
                WHERE user_id = ? AND study_date >= ? AND study_date < ?
                """, Integer.class, userId, Date.valueOf(from), Date.valueOf(beforeExclusive));
        return sum == null ? 0 : sum;
    }

    /** "자격증|과목" → 이 계획의 그 과목 할 일에 연결해 기록한 시간(분) */
    public Map<String, Integer> doneBySubject(long userId, long planId) {
        Map<String, Integer> done = new java.util.HashMap<>();
        jdbc.query("""
                SELECT t.study_category, t.subject_name, COALESCE(SUM(s.actual_minutes), 0) AS minutes
                FROM STUDY_SESSIONS s
                JOIN STUDY_PLAN_DETAILS t ON t.task_id = s.task_id AND t.user_id = s.user_id
                WHERE s.user_id = ? AND t.plan_id = ?
                GROUP BY t.study_category, t.subject_name
                """, rs -> {
            done.put(rs.getString("study_category") + "|" + rs.getString("subject_name"), rs.getInt("minutes"));
        }, userId, planId);
        return done;
    }

    /** 이 계획의 재편성 추천을 최근 days 일 안에 거절했는가 (그동안은 다시 묻지 않는다) */
    public boolean dismissedRecently(long userId, long planId, int days) {
        Integer count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM AI_PLAN_PROPOSALS
                WHERE user_id = ? AND current_plan_id = ? AND delay_reason_type = ?
                  AND acceptance_status = 'REJECTED' AND created_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
                """, Integer.class, userId, planId, REASON_BEHIND, days);
        return count != null && count > 0;
    }

    /** 추천을 수락(proposedPlanId = 새 계획)했거나 거절(proposedPlanId = null)한 기록을 남긴다. */
    public void recordProposal(long userId, long currentPlanId, Long proposedPlanId, String note, String result) {
        boolean accepted = proposedPlanId != null;
        jdbc.update("""
                INSERT INTO AI_PLAN_PROPOSALS (user_id, current_plan_id, proposed_plan_id, delay_reason_type, delay_note,
                       model_name, proposal_result, acceptance_status, accepted_at)
                VALUES (?, ?, ?, ?, ?, 'RULE', ?, ?, ?)
                """, userId, currentPlanId, proposedPlanId, REASON_BEHIND,
                note == null || note.length() <= 500 ? note : note.substring(0, 500), result,
                accepted ? "ACCEPTED" : "REJECTED",
                accepted ? java.sql.Timestamp.valueOf(java.time.LocalDateTime.now()) : null);
    }

    private void requireOwned(long userId, long planId) {
        Integer found = jdbc.queryForObject("""
                SELECT COUNT(*) FROM STUDY_PLANS
                WHERE plan_id = ? AND user_id = ? AND plan_type = ? AND status IN ('ACTIVE', 'REPLACED')
                FOR UPDATE
                """, Integer.class, planId, userId, PLAN_TYPE);
        if (found == null || found == 0) throw new IllegalArgumentException("저장한 계획을 찾을 수 없습니다.");
    }

    /** condition 은 이 클래스 안에서 만든 고정 문장만 넘긴다 (사용자 입력 아님). */
    private SavedPlan load(long userId, String condition) {
        List<SavedPlan> plans = jdbc.query("""
                SELECT plan_id, plan_name, version_no, start_date, end_date FROM STUDY_PLANS
                WHERE user_id = ? AND plan_type = ? AND\s""" + condition + """
                 ORDER BY plan_id DESC LIMIT 1
                """, (rs, n) -> new SavedPlan(rs.getLong("plan_id"), rs.getString("plan_name"), rs.getInt("version_no"),
                rs.getObject("start_date", LocalDate.class), rs.getObject("end_date", LocalDate.class), List.of()),
                userId, PLAN_TYPE);
        if (plans.isEmpty()) return null;
        SavedPlan p = plans.get(0);
        List<Task> tasks = jdbc.query("""
                SELECT scheduled_date, study_category, subject_name, estimated_minutes FROM STUDY_PLAN_DETAILS
                WHERE plan_id = ? AND user_id = ? ORDER BY scheduled_date, task_id
                """, (rs, n) -> new Task(rs.getObject("scheduled_date", LocalDate.class), rs.getString("study_category"),
                rs.getString("subject_name"), rs.getInt("estimated_minutes")), p.planId(), userId);
        return new SavedPlan(p.planId(), p.planName(), p.versionNo(), p.startDate(), p.endDate(), tasks);
    }
}
