package com.passpace.repository;

import com.passpace.constant.MajorType;
import com.passpace.domain.UserStudyProfile;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * [한결 → 동건 제공] 공통 계약 UserStudyProfileQuery 구현.
 * 챗봇이 "시험일·하루 시간"이 빠진 질문을 받으면 마이페이지에 저장된 목표로 채운다.
 */
@Component
public class JdbcUserStudyProfileQuery implements UserStudyProfileQuery {

    private final JdbcTemplate jdbc;
    private final String examCode;

    public JdbcUserStudyProfileQuery(JdbcTemplate jdbc, @Value("${passpace.certification-code}") String examCode) {
        this.jdbc = jdbc;
        this.examCode = examCode;
    }

    @Override
    public Optional<UserStudyProfile> findByUserId(Long userId) {
        // TODO(한결): 구현
        if (userId == null) {
            return Optional.empty();
        }

        String sql = """
                SELECT u.user_id,
                       u.major_type,
                       g.target_exam_date,
                       g.daily_minutes,
                       s.subject_name,
                       gs.familiarity_level
                FROM USERS u
                LEFT JOIN USER_GOALS g
                    ON g.goal_id = (
                        SELECT ug.goal_id
                        FROM USER_GOALS ug
                        WHERE ug.user_id = u.user_id
                          AND ug.certification_id = (
                              SELECT MIN(c.certification_id)
                              FROM CERTIFICATIONS c
                              WHERE c.source_exam_code = ?
                          )
                          AND ug.status = 'ACTIVE'
                        ORDER BY ug.created_at DESC, ug.goal_id DESC
                        LIMIT 1
                    )
                LEFT JOIN GOAL_SUBJECTS gs
                    ON gs.goal_id = g.goal_id
                LEFT JOIN CERTIFICATION_SUBJECTS s
                    ON s.certification_subject_id = gs.certification_subject_id
                   AND s.certification_id = g.certification_id
                   AND s.exam_type = 'WRITTEN'
                WHERE u.user_id = ?
                ORDER BY s.display_order,
                         s.certification_subject_id,
                         gs.goal_subject_id
                """;

        return jdbc.query(
                sql,
                rs -> {
                    if (!rs.next()) {
                        return Optional.<UserStudyProfile>empty();
                    }

                    Long foundUserId = rs.getLong("user_id");

                    MajorType majorType = MajorType.fromCode(
                            rs.getString("major_type")
                    );

                    LocalDate targetExamDate = rs.getObject(
                            "target_exam_date", LocalDate.class
                    );

                    Integer dailyMinutes = rs.getObject(
                            "daily_minutes", Integer.class
                    );

                    Map<String, Integer> familiarityBySubject =
                            new LinkedHashMap<>();

                    do {
                        String subjectName = rs.getString("subject_name");
                        Integer level = rs.getObject(
                                "familiarity_level", Integer.class
                        );

                        if (subjectName != null
                                && level != null
                                && level >= 1
                                && level <= 3) {
                            familiarityBySubject.put(subjectName, level);
                        }
                    } while (rs.next());

                    return Optional.of(new UserStudyProfile(
                            foundUserId,
                            majorType,
                            targetExamDate,
                            dailyMinutes,
                            familiarityBySubject
                    ));
                },
                examCode,
                userId
        );
    }
}
