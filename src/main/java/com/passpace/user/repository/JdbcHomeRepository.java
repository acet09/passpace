package com.passpace.user.repository;

import com.passpace.common.code.ExamType;
import com.passpace.user.dto.UserViews.UpcomingExam;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.List;

/** [한결] 메인 페이지 시험 일정 조회 */
@Repository
public class JdbcHomeRepository implements HomeRepository {

    private final JdbcTemplate jdbc;

    public JdbcHomeRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public List<UpcomingExam> findUpcomingExams(String examCode, int limit) {
        // TODO(한결): 구현
        if (limit <= 0) {
            return List.of();
        }
        LocalDate today = LocalDate.now();

        String sql = """
                SELECT exam_year,
                       round_no,
                       exam_type,
                       reg_start_at,
                       reg_end_at,
                       COALESCE(exam_start_date, exam_date) AS display_start_date,
                       COALESCE(exam_end_date, exam_start_date, exam_date) AS display_end_date,
                       result_date,
                       source_id
                FROM EXAM_ROUNDS
                WHERE source_exam_code = ?
                  AND COALESCE(exam_start_date, exam_date) >= ?
                ORDER BY display_start_date ASC,
                         exam_year ASC,
                         round_no ASC,
                         exam_type ASC
                LIMIT ?
                """;

        return jdbc.query(
                sql,
                (rs, rowNum) -> {

                    LocalDate examStartDate = rs.getObject(
                            "display_start_date", LocalDate.class
                    );

                    LocalDate examEndDate = rs.getObject(
                            "display_end_date", LocalDate.class
                    );

                    ExamType examType = ExamType.fromCode(
                            rs.getString("exam_type")
                    );

                    String examTypeLabel = examType == null
                            ? "미정"
                            : examType.getLabel();

                    long daysLeft = ChronoUnit.DAYS.between(
                            today, examStartDate
                    );

                    boolean sample = rs.getLong("source_id") == 2L;

                    return new UpcomingExam(
                            rs.getInt("exam_year"),
                            rs.getInt("round_no"),
                            examTypeLabel,
                            rs.getObject("reg_start_at", LocalDateTime.class),
                            rs.getObject("reg_end_at", LocalDateTime.class),
                            examStartDate,
                            examEndDate,
                            rs.getObject("result_date", LocalDate.class),
                            daysLeft,
                            sample
                    );
                },
                examCode,
                today,
                limit
        );
    }
}
