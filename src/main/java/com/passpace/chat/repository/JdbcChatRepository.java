package com.passpace.chat.repository;

import com.passpace.common.code.ExamType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Repository;

import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

/** [동건] 챗봇 저장소 JDBC 구현 */
@Repository
public class JdbcChatRepository implements ChatRepository {

    private final JdbcTemplate jdbc;

    public JdbcChatRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public Optional<Long> findCertificationId(String examCode) {
        List<Long> ids = jdbc.query("SELECT certification_id FROM CERTIFICATIONS WHERE source_exam_code = ? AND active_yn = 'Y' LIMIT 1",
                (rs, i) -> rs.getLong(1), examCode);
        return ids.stream().findFirst();
    }

    @Override
    public Optional<String> findPassCriteria(long certificationId) {
        List<String> items = jdbc.query("SELECT pass_criteria FROM CERTIFICATIONS WHERE certification_id = ?",
                (rs, i) -> rs.getString(1), certificationId);
        return items.stream().filter(v -> v != null && !v.isBlank()).findFirst();
    }

    @Override
    public Optional<LocalDate> findNearestExamStart(long certificationId, ExamType examType, LocalDate today) {
        List<LocalDate> dates = jdbc.query("""
                SELECT COALESCE(exam_start_date, exam_date) AS start_date FROM EXAM_ROUNDS
                WHERE certification_id = ? AND exam_type = ?
                  AND COALESCE(exam_start_date, exam_date) >= ?
                ORDER BY start_date ASC LIMIT 1
                """, (rs, i) -> rs.getDate(1).toLocalDate(), certificationId, examType.name(), Date.valueOf(today));
        return dates.stream().findFirst();
    }

    @Override
    public List<String> findSubjectNames(long certificationId, ExamType examType) {
        return jdbc.query("""
                SELECT subject_name FROM CERTIFICATION_SUBJECTS
                WHERE certification_id = ? AND exam_type = ?
                ORDER BY display_order ASC, certification_subject_id ASC
                """, (rs, i) -> rs.getString(1), certificationId, examType.name());
    }

    @Override
    public Long createConversation(Long userId, String title) {
        KeyHolder holder = new GeneratedKeyHolder();
        jdbc.update(con -> {
            PreparedStatement ps = con.prepareStatement(
                    "INSERT INTO CHAT_CONVERSATIONS (user_id, title, status) VALUES (?, ?, 'ACTIVE')",
                    Statement.RETURN_GENERATED_KEYS);
            ps.setLong(1, userId);
            ps.setString(2, title);
            return ps;
        }, holder);
        if (holder.getKey() == null) throw new IllegalStateException("대화방 생성에 실패했습니다.");
        return holder.getKey().longValue();
    }

    @Override
    public boolean isOwner(Long conId, Long userId) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM CHAT_CONVERSATIONS WHERE con_id = ? AND user_id = ?",
                Integer.class, conId, userId);
        return count != null && count > 0;
    }

    @Override
    public void insertMessage(Long conId, String role, String content) {
        jdbc.update("INSERT INTO CHAT_MESSAGES (con_id, role, content) VALUES (?, ?, ?)", conId, role, content);
    }

    @Override
    public List<String> findRecentUserMessages(Long conId, int limit) {
        if (limit <= 0) return List.of();
        return jdbc.query("""
                SELECT content FROM CHAT_MESSAGES
                WHERE con_id = ? AND role = 'user'
                ORDER BY message_id DESC LIMIT ?
                """, (rs, i) -> rs.getString(1), conId, limit);
    }
}
