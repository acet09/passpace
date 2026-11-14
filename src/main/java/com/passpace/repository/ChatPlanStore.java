package com.passpace.repository;

import com.passpace.service.MultiGoalPlanCalculator.Allocation;
import com.passpace.service.MultiGoalPlanCalculator.DaySchedule;
import com.passpace.service.MultiGoalPlanCalculator.PlanResponse;
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
 * 다시 저장하면 이전 챗봇 계획은 status = 'REPLACED' 로 바꾸고 새 계획을 ACTIVE 로 넣는다.
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

    private final JdbcTemplate jdbc;

    public ChatPlanStore(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * @param subjectIds "목표키|과목명" → CERTIFICATION_SUBJECTS ID (모르면 없어도 됨)
     * @return 새 계획 ID
     */
    @Transactional
    public long replace(long userId, PlanResponse plan, Map<String, Long> subjectIds) {
        if (plan.days().isEmpty()) throw new IllegalArgumentException("저장할 날짜별 계획이 없습니다.");
        jdbc.update("UPDATE STUDY_PLANS SET status = 'REPLACED' WHERE user_id = ? AND plan_type = ? AND status = 'ACTIVE'",
                userId, PLAN_TYPE);
        Integer version = jdbc.queryForObject(
                "SELECT COALESCE(MAX(version_no), 0) + 1 FROM STUDY_PLANS WHERE user_id = ? AND plan_type = ?",
                Integer.class, userId, PLAN_TYPE);
        LocalDate start = plan.days().get(0).date();
        LocalDate end = plan.days().get(plan.days().size() - 1).date();
        String name = "챗봇 학습계획 (" + String.join(" + ",
                plan.goals().stream().map(g -> g.certificationName()).toList()) + ", 하루 " + plan.dailyMinutes() + "분)";
        String planName = name.length() <= 200 ? name : name.substring(0, 200);

        KeyHolder key = new GeneratedKeyHolder();
        jdbc.update(con -> {
            PreparedStatement ps = con.prepareStatement("""
                    INSERT INTO STUDY_PLANS (user_id, plan_name, plan_type, version_no, start_date, end_date, status)
                    VALUES (?, ?, ?, ?, ?, ?, 'ACTIVE')
                    """, Statement.RETURN_GENERATED_KEYS);
            ps.setLong(1, userId);
            ps.setString(2, planName);
            ps.setString(3, PLAN_TYPE);
            ps.setInt(4, version == null ? 1 : version);
            ps.setDate(5, Date.valueOf(start));
            ps.setDate(6, Date.valueOf(end));
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
        List<SavedPlan> plans = jdbc.query("""
                SELECT plan_id, plan_name, version_no, start_date, end_date FROM STUDY_PLANS
                WHERE user_id = ? AND plan_type = ? AND status = 'ACTIVE'
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
