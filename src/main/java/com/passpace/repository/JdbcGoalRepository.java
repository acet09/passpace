package com.passpace.repository;

import com.passpace.dto.user.UserViews.ActiveGoal;
import com.passpace.dto.user.UserViews.ExamRoundOption;
import com.passpace.dto.user.UserViews.SubjectOption;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Repository;

import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.sql.Types;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/** [한결] 학습 목표 JDBC 구현 */
@Repository
public class JdbcGoalRepository implements GoalRepository {

    private final JdbcTemplate jdbc;

    public JdbcGoalRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public Optional<Long> findCertificationId(String examCode) {
        // TODO(한결): 구현
        String sql = """
                SELECT certification_id
                FROM CERTIFICATIONS
                WHERE source_exam_code = ?
                ORDER BY certification_id
                LIMIT 1
                """;

        List<Long> ids = jdbc.query(
                sql,
                (rs, rowNum) -> rs.getLong("certification_id"),
                examCode
        );

        return ids.stream().findFirst();
    }

    @Override
    public List<ExamRoundOption> findUpcomingWrittenRounds(long certificationId) {
        // TODO(한결): 구현
        String sql = """
                SELECT exam_round_id, exam_year, round_no, source_id,
                       COALESCE(exam_start_date, exam_date) AS start_date
                FROM EXAM_ROUNDS
                WHERE certification_id = ?
                  AND exam_type = 'WRITTEN'
                  AND COALESCE(exam_start_date, exam_date) >= ?
                ORDER BY start_date, exam_year, round_no, exam_round_id
                """;

        return jdbc.query(
                sql,
                (rs, rowNum) -> {
                    LocalDate startDate = rs.getObject(
                            "start_date", LocalDate.class
                    );

                    String label = rs.getInt("exam_year") + "년 "
                            + rs.getInt("round_no") + "회 필기 ("
                            + startDate + ")";

                    if (rs.getLong("source_id") == 2L) {
                        label += " · 샘플";
                    }

                    return new ExamRoundOption(
                            rs.getLong("exam_round_id"),
                            label,
                            startDate
                    );
                },
                certificationId,
                LocalDate.now()
        );
    }

    @Override
    public Optional<LocalDate> findRoundStartDate(Long examRoundId) {
        // TODO(한결): 구현
        if (examRoundId == null) {
            return Optional.empty();
        }

        String sql = """
                SELECT COALESCE(exam_start_date, exam_date) AS start_date
                FROM EXAM_ROUNDS
                WHERE exam_round_id = ?
                  AND COALESCE(exam_start_date, exam_date) IS NOT NULL
                """;

        List<LocalDate> dates = jdbc.query(
                sql,
                (rs, rowNum) -> rs.getObject("start_date", LocalDate.class),
                examRoundId
        );

        return dates.stream().findFirst();
    }

    @Override
    public List<SubjectOption> findWrittenSubjects(long certificationId) {
        // TODO(한결): 구현
        String sql = """
                SELECT certification_subject_id, subject_name
                FROM CERTIFICATION_SUBJECTS
                WHERE certification_id = ?
                  AND exam_type = 'WRITTEN'
                ORDER BY display_order, certification_subject_id
                """;

        return jdbc.query(
                sql,
                (rs, rowNum) -> new SubjectOption(
                        rs.getLong("certification_subject_id"),
                        rs.getString("subject_name")
                ),
                certificationId
        );
    }

    @Override
    public Optional<ActiveGoal> findActiveGoal(Long userId, long certificationId) {
        // TODO(한결): 구현
        String sql = """
                SELECT goal_id, target_exam_round_id, target_exam_date,
                       daily_minutes
                FROM USER_GOALS
                WHERE user_id = ?
                  AND certification_id = ?
                  AND status = 'ACTIVE'
                ORDER BY created_at DESC, goal_id DESC
                LIMIT 1
                """;

        List<ActiveGoal> goals = jdbc.query(
                sql,
                (rs, rowNum) -> new ActiveGoal(
                        rs.getLong("goal_id"),
                        rs.getObject("target_exam_round_id", Long.class),
                        rs.getObject("target_exam_date", LocalDate.class),
                        rs.getObject("daily_minutes", Integer.class)
                ),
                userId,
                certificationId
        );

        return goals.stream().findFirst();
    }

    @Override
    public Map<Long, Integer> findFamiliarity(Long goalId) {
        // TODO(한결): 구현
        Map<Long, Integer> result = new LinkedHashMap<>();

        if (goalId == null) {
            return result;
        }

        String sql = """
                SELECT certification_subject_id, familiarity_level
                FROM GOAL_SUBJECTS
                WHERE goal_id = ?
                  AND familiarity_level IS NOT NULL
                ORDER BY certification_subject_id
                """;

        jdbc.query(
                sql,
                rs -> {
                    result.put(
                            rs.getLong("certification_subject_id"),
                            rs.getInt("familiarity_level")
                    );
                },
                goalId
        );

        return result;
    }

    @Override
    public Long insertGoal(Long userId, long certificationId, Long examRoundId, LocalDate targetExamDate,
                           String goalTitle, Integer dailyMinutes) {
        // TODO(한결): 구현
        String sql = """
                INSERT INTO USER_GOALS (
                    user_id, certification_id, target_exam_round_id,
                    target_exam_date, goal_title, daily_minutes,
                    status, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, 'ACTIVE', NOW())
                """;

        KeyHolder keyHolder = new GeneratedKeyHolder();

        jdbc.update(connection -> {
            PreparedStatement ps = connection.prepareStatement(
                    sql, Statement.RETURN_GENERATED_KEYS
            );

            ps.setLong(1, userId);
            ps.setLong(2, certificationId);
            setNullableLong(ps, 3, examRoundId);
            ps.setObject(
                    4,
                    targetExamDate == null ? null : Date.valueOf(targetExamDate),
                    Types.DATE
            );
            ps.setString(5, goalTitle);
            ps.setObject(6, dailyMinutes, Types.INTEGER);

            return ps;
        }, keyHolder);

        // 추가된 코드: DB가 생성한 목표 번호 반환
        Number key = keyHolder.getKey();

        if (key == null) {
            throw new IllegalStateException("생성된 목표 번호를 가져오지 못했습니다.");
        }

        return key.longValue();
    }

    @Override
    public void updateGoal(Long goalId, Long examRoundId, LocalDate targetExamDate, Integer dailyMinutes) {
        // TODO(한결): 구현
        String sql = """
                UPDATE USER_GOALS
                SET target_exam_round_id = ?,
                    target_exam_date = ?,
                    daily_minutes = ?
                WHERE goal_id = ?
                """;

        jdbc.update(connection -> {
            PreparedStatement ps = connection.prepareStatement(sql);

            setNullableLong(ps, 1, examRoundId);
            ps.setObject(
                    2,
                    targetExamDate == null ? null : Date.valueOf(targetExamDate),
                    Types.DATE
            );
            ps.setObject(3, dailyMinutes, Types.INTEGER);
            ps.setLong(4, goalId);

            return ps;
        });
    }

    @Override
    public void saveFamiliarity(Long goalId, Long subjectId, int level) {
        // TODO(한결): 구현
        String countSql = """
                SELECT COUNT(*)
                FROM GOAL_SUBJECTS
                WHERE goal_id = ?
                  AND certification_subject_id = ?
                """;

        Long count = jdbc.queryForObject(
                countSql, Long.class, goalId, subjectId
        );

        if (count != null && count > 0) {
            String updateSql = """
                    UPDATE GOAL_SUBJECTS
                    SET familiarity_level = ?
                    WHERE goal_id = ?
                      AND certification_subject_id = ?
                    """;

            jdbc.update(updateSql, level, goalId, subjectId);
        } else {
            String insertSql = """
                    INSERT INTO GOAL_SUBJECTS (
                        goal_id, certification_subject_id, familiarity_level
                    )
                    VALUES (?, ?, ?)
                    """;

            jdbc.update(insertSql, goalId, subjectId, level);
        }
    }

    private static void setNullableLong(PreparedStatement ps, int index, Long value) throws java.sql.SQLException {
        // TODO(한결): 구현
        if (value == null) {
            ps.setNull(index, Types.BIGINT);
        } else {
            ps.setLong(index, value);
        }
    }
}
