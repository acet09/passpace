package com.passpace.repository;

import com.passpace.dto.collect.CollectDataView.CountRow;
import com.passpace.dto.collect.CollectDataView.ReviewPage;
import com.passpace.dto.collect.CollectDataView.ReviewRow;
import com.passpace.dto.collect.CollectDataView.Summary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * [용성·11-14] 관리자 "수집 데이터" 화면 조회 (SELECT 만, DB 변경 없음)
 *
 * 출처 구분 (DATA_SOURCES 행을 추가하지 않았으므로 번호 + 주소로 나눈다)
 *  VELOG(source_id 3) · TISTORY(7) · NAVER_BLOG(주소 blog.naver.com) · NAVER_CAFE(cafe.naver.com) · DUMMY(4) · OTHER
 */
@Repository
public class JdbcCollectDataQuery {

    static final String SOURCE_CASE = """
            CASE
              WHEN p.source_id = 3 THEN 'VELOG'
              WHEN p.source_id = 7 THEN 'TISTORY'
              WHEN p.source_id = 4 THEN 'DUMMY'
              WHEN p.source_id IS NULL AND p.source_url LIKE 'https://blog.naver.com/%' THEN 'NAVER_BLOG'
              WHEN p.source_id IS NULL AND p.source_url LIKE 'https://cafe.naver.com/%' THEN 'NAVER_CAFE'
              ELSE 'OTHER' END""";

    private static final Set<String> SOURCES = Set.of("VELOG", "TISTORY", "NAVER_BLOG", "NAVER_CAFE", "DUMMY", "OTHER");
    private static final Set<String> STATUSES = Set.of("VALID", "PENDING", "EXCLUDED");

    /** 정렬 가능한 열 (화면 열 이름 → SQL). 목록에 없는 값은 번호 내림차순 */
    private static final Map<String, String> SORT_COLUMNS = Map.ofEntries(
            Map.entry("id", "p.review_id"), Map.entry("source", SOURCE_CASE),
            Map.entry("cert", "c.certification_id"), Map.entry("exam", "p.exam_type"),
            Map.entry("status", "p.review_status"), Map.entry("pass", "p.pass_yn"),
            Map.entry("major", "p.major_type"), Map.entry("prep", "p.prep_days"),
            Map.entry("daily", "p.daily_minutes"), Map.entry("total", "p.total_hours"),
            Map.entry("subjects", "p.study_subjects"), Map.entry("method", "p.study_method"),
            Map.entry("summary", "p.evidence_text"), Map.entry("posted", "p.posted_at"),
            Map.entry("collected", "p.collected_at"), Map.entry("url", "p.source_url"));

    private final JdbcTemplate jdbc;

    public JdbcCollectDataQuery(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Summary summary() {
        List<CountRow> bySource = jdbc.query("SELECT " + SOURCE_CASE + " AS src, p.review_status AS st, COUNT(*) AS n "
                        + "FROM PASS_REVIEWS p GROUP BY src, st ORDER BY src, st",
                (rs, i) -> new CountRow(rs.getString("src"), rs.getString("st"), rs.getLong("n")));
        List<CountRow> byCert = jdbc.query("""
                        SELECT c.cert_name AS cert, p.review_status AS st, COUNT(*) AS n
                        FROM PASS_REVIEWS p JOIN CERTIFICATIONS c ON c.certification_id = p.certification_id
                        GROUP BY c.certification_id, c.cert_name, p.review_status
                        ORDER BY c.certification_id, p.review_status""",
                (rs, i) -> new CountRow(rs.getString("cert"), rs.getString("st"), rs.getLong("n")));
        Long total = jdbc.queryForObject("SELECT COUNT(*) FROM PASS_REVIEWS", Long.class);
        List<LocalDateTime> last = jdbc.query("SELECT MAX(collected_at) AS t FROM PASS_REVIEWS",
                (rs, i) -> rs.getObject("t", LocalDateTime.class));
        return new Summary(bySource, byCert, total == null ? 0 : total, last.isEmpty() ? null : last.get(0));
    }

    /**
     * @param source ALL 또는 VELOG·TISTORY·NAVER_BLOG·NAVER_CAFE·DUMMY·OTHER
     * @param cert   ALL 또는 자격증 코드(1320·SQLD·CA1·ADSP)
     * @param status ALL 또는 VALID·PENDING·EXCLUDED
     * @param keyword 요약문·주소에 들어 있는 글자 (없으면 전체)
     * @param sort   정렬 열 (SORT_COLUMNS 의 키), dir asc·desc. 빈 값(NULL)은 항상 맨 뒤
     */
    public ReviewPage reviews(String source, String cert, String status, String keyword,
                              String sort, String dir, int page, int size) {
        int sz = Math.max(10, Math.min(200, size));
        int pg = Math.max(0, page);
        StringBuilder where = new StringBuilder(" WHERE 1 = 1");
        List<Object> args = new ArrayList<>();
        if (source != null && SOURCES.contains(source)) {
            where.append(" AND ").append(SOURCE_CASE).append(" = ?");
            args.add(source);
        }
        if (cert != null && !cert.isBlank() && !"ALL".equals(cert)) {
            where.append(" AND c.source_exam_code = ?");
            args.add(cert);
        }
        if (status != null && STATUSES.contains(status)) {
            where.append(" AND p.review_status = ?");
            args.add(status);
        }
        if (keyword != null && !keyword.isBlank()) {
            where.append(" AND (p.evidence_text LIKE ? OR p.source_url LIKE ? OR p.exclude_reason LIKE ?)");
            String k = "%" + keyword.strip() + "%";
            args.add(k);
            args.add(k);
            args.add(k);
        }
        String from = " FROM PASS_REVIEWS p JOIN CERTIFICATIONS c ON c.certification_id = p.certification_id";
        Long total = jdbc.queryForObject("SELECT COUNT(*)" + from + where, Long.class, args.toArray());

        String col = sort == null ? null : SORT_COLUMNS.get(sort);
        String orderBy = col == null ? " ORDER BY p.review_id DESC"
                : " ORDER BY (" + col + ") IS NULL, " + col + ("asc".equalsIgnoreCase(dir) ? " ASC" : " DESC")
                + ", p.review_id DESC";

        List<Object> pageArgs = new ArrayList<>(args);
        pageArgs.add(sz);
        pageArgs.add(pg * sz);
        List<ReviewRow> rows = jdbc.query("SELECT p.review_id, " + SOURCE_CASE + " AS src, c.cert_name, p.exam_type,"
                        + " p.review_status, p.exclude_reason, p.pass_yn, p.major_type, p.prep_days, p.daily_minutes,"
                        + " p.total_hours, p.study_subjects, p.study_method, p.evidence_text, p.posted_at, p.source_url,"
                        + " p.collected_at" + from + where + orderBy + " LIMIT ? OFFSET ?",
                (rs, i) -> new ReviewRow(rs.getLong("review_id"), rs.getString("src"), rs.getString("cert_name"),
                        rs.getString("exam_type"), rs.getString("review_status"), rs.getString("exclude_reason"),
                        rs.getString("pass_yn"), rs.getString("major_type"),
                        rs.getObject("prep_days", Integer.class), rs.getObject("daily_minutes", Integer.class),
                        rs.getBigDecimal("total_hours"), rs.getString("study_subjects"), rs.getString("study_method"),
                        rs.getString("evidence_text"), rs.getObject("posted_at", LocalDate.class),
                        rs.getString("source_url"), rs.getObject("collected_at", LocalDateTime.class)),
                pageArgs.toArray());
        return new ReviewPage(total == null ? 0 : total, pg, sz, rows);
    }
}
