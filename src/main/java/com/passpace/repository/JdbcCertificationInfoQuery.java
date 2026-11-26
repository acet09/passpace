package com.passpace.repository;

import com.passpace.constant.ExamType;
import com.passpace.dto.cert.CertificationViews.PassRate;
import com.passpace.dto.cert.CertificationViews.Round;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/** [11-26] 지원 자격증 정보 메뉴 조회. CERTIFICATION_INFO 가 없는 자격증도 나오도록 LEFT JOIN */
@Repository
public class JdbcCertificationInfoQuery implements CertificationInfoQuery {

    /** 06_projected_2027_schedule.sql 의 예상 일정 출처 (JdbcHomeRepository 와 같은 기준) */
    private static final long PROJECTED_SOURCE_ID = 2L;

    private static final String CERT_SQL = """
            SELECT c.certification_id, c.cert_name, c.cert_type, c.issuing_org, c.pass_criteria,
                   i.grade, i.category, i.summary, i.eligibility, i.eligibility_check_url, i.always_open_yn,
                   i.written_exemption, i.required_items, i.validity, i.refund_note, i.refund_url,
                   i.result_notice, i.related_certs, i.official_url, i.apply_url, i.info_verified_at
            FROM CERTIFICATIONS c
            LEFT JOIN CERTIFICATION_INFO i ON i.certification_id = c.certification_id
            WHERE c.active_yn = 'Y'
            """;

    private static final String ROUND_SQL = """
            SELECT certification_id, exam_year, round_no, exam_type, reg_start_at, reg_end_at,
                   add_reg_start_at, add_reg_end_at,
                   COALESCE(exam_start_date, exam_date) AS start_date,
                   COALESCE(exam_end_date, exam_start_date, exam_date) AS end_date,
                   result_date, source_id
            FROM EXAM_ROUNDS
            WHERE exam_year >= ?
            """;

    private final JdbcTemplate jdbc;

    public JdbcCertificationInfoQuery(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public List<CertRow> findActive() {
        return jdbc.query(CERT_SQL + " ORDER BY c.certification_id", CERT_MAPPER);
    }

    @Override
    public Optional<CertRow> findActive(long certificationId) {
        return jdbc.query(CERT_SQL + " AND c.certification_id = ?", CERT_MAPPER, certificationId).stream().findFirst();
    }

    @Override
    public List<ExamInfoRow> findExamInfos(long certificationId) {
        return jdbc.query("""
                SELECT exam_type, exam_fee, question_count, duration_minutes, exam_method, pass_criteria, scope_year
                FROM CERTIFICATION_EXAM_INFO
                WHERE certification_id = ?
                ORDER BY CASE exam_type WHEN 'WRITTEN' THEN 0 ELSE 1 END
                """, (rs, n) -> new ExamInfoRow(rs.getString("exam_type"), intOrNull(rs, "exam_fee"),
                intOrNull(rs, "question_count"), intOrNull(rs, "duration_minutes"), rs.getString("exam_method"),
                rs.getString("pass_criteria"), intOrNull(rs, "scope_year")), certificationId);
    }

    @Override
    public Map<String, List<String>> findSubjects(long certificationId) {
        Map<String, List<String>> out = new LinkedHashMap<>();
        jdbc.query("""
                SELECT exam_type, subject_name
                FROM CERTIFICATION_SUBJECTS
                WHERE certification_id = ?
                ORDER BY CASE exam_type WHEN 'WRITTEN' THEN 0 ELSE 1 END, display_order, certification_subject_id
                """, rs -> {
            String type = rs.getString("exam_type") == null ? "WRITTEN" : rs.getString("exam_type").toUpperCase();
            out.computeIfAbsent(type, k -> new ArrayList<>()).add(rs.getString("subject_name"));
        }, certificationId);
        return out;
    }

    @Override
    public Map<Long, List<String>> findExamTypes() {
        Map<Long, Set<String>> found = new LinkedHashMap<>();
        jdbc.query("""
                SELECT certification_id, UPPER(exam_type) AS exam_type FROM CERTIFICATION_SUBJECTS WHERE exam_type IS NOT NULL
                UNION SELECT certification_id, UPPER(exam_type) FROM EXAM_ROUNDS WHERE exam_type IS NOT NULL
                UNION SELECT certification_id, UPPER(exam_type) FROM CERTIFICATION_EXAM_INFO
                """, rs -> {
            found.computeIfAbsent(rs.getLong("certification_id"), k -> new LinkedHashSet<>()).add(rs.getString("exam_type"));
        });
        Map<Long, List<String>> out = new LinkedHashMap<>();
        found.forEach((id, types) -> out.put(id, types.stream()
                .filter(t -> ExamType.fromCode(t) != null)
                .sorted((a, b) -> Integer.compare(ExamType.fromCode(a).ordinal(), ExamType.fromCode(b).ordinal()))
                .toList()));
        return out;
    }

    @Override
    public List<Round> findRounds(long certificationId, int fromYear, LocalDate today) {
        return jdbc.query(ROUND_SQL + " AND certification_id = ? ORDER BY exam_year, round_no, exam_type DESC",
                roundMapper(today), fromYear, certificationId).stream().map(r -> r.round).toList();
    }

    @Override
    public Map<Long, List<Round>> findRoundsAll(int fromYear, LocalDate today) {
        Map<Long, List<Round>> out = new LinkedHashMap<>();
        for (IdRound r : jdbc.query(ROUND_SQL + " ORDER BY exam_year, round_no, exam_type DESC", roundMapper(today), fromYear)) {
            out.computeIfAbsent(r.certificationId, k -> new ArrayList<>()).add(r.round);
        }
        return out;
    }

    @Override
    public List<PassRate> findPassRates(long certificationId, int limit) {
        return jdbc.query("""
                SELECT exam_year, round_no, exam_type, applicant_count, pass_count, pass_rate
                FROM EXAM_ROUNDS
                WHERE certification_id = ? AND pass_rate IS NOT NULL
                ORDER BY exam_year DESC, round_no DESC, exam_type
                LIMIT ?
                """, (rs, n) -> {
            BigDecimal rate = rs.getBigDecimal("pass_rate");
            return new PassRate(intOrNull(rs, "exam_year"), intOrNull(rs, "round_no"), label(rs.getString("exam_type")),
                    intOrNull(rs, "applicant_count"), intOrNull(rs, "pass_count"), rate == null ? null : rate.doubleValue());
        }, certificationId, limit);
    }

    // ---------------------------------------------------------------------

    private record IdRound(long certificationId, Round round) {
    }

    private static RowMapper<IdRound> roundMapper(LocalDate today) {
        return (rs, n) -> {
            LocalDate start = rs.getObject("start_date", LocalDate.class);
            LocalDate end = rs.getObject("end_date", LocalDate.class);
            LocalDate result = rs.getObject("result_date", LocalDate.class);
            LocalDate last = result != null ? result : (end != null ? end : start);
            String type = rs.getString("exam_type");
            Round round = new Round(intOrNull(rs, "exam_year"), intOrNull(rs, "round_no"),
                    type == null ? null : type.toUpperCase(), label(type),
                    rs.getObject("reg_start_at", LocalDateTime.class), rs.getObject("reg_end_at", LocalDateTime.class),
                    rs.getObject("add_reg_start_at", LocalDateTime.class), rs.getObject("add_reg_end_at", LocalDateTime.class),
                    start, end, result, last != null && last.isBefore(today),
                    rs.getLong("source_id") == PROJECTED_SOURCE_ID);
            return new IdRound(rs.getLong("certification_id"), round);
        };
    }

    private static final RowMapper<CertRow> CERT_MAPPER = (rs, n) -> new CertRow(
            rs.getLong("certification_id"), rs.getString("cert_name"), rs.getString("cert_type"),
            rs.getString("issuing_org"), rs.getString("pass_criteria"), rs.getString("grade"),
            rs.getString("category"), rs.getString("summary"), rs.getString("eligibility"),
            rs.getString("eligibility_check_url"), "Y".equalsIgnoreCase(rs.getString("always_open_yn")),
            rs.getString("written_exemption"), rs.getString("required_items"), rs.getString("validity"),
            rs.getString("refund_note"), rs.getString("refund_url"), rs.getString("result_notice"),
            rs.getString("related_certs"), rs.getString("official_url"), rs.getString("apply_url"),
            rs.getObject("info_verified_at", LocalDate.class));

    private static String label(String examType) {
        ExamType t = ExamType.fromCode(examType);
        return t == null ? null : t.getLabel();
    }

    private static Integer intOrNull(ResultSet rs, String col) throws SQLException {
        int v = rs.getInt(col);
        return rs.wasNull() ? null : v;
    }
}
