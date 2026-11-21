package com.passpace.repository;

import com.passpace.dto.collect.CollectDtos.DbStatus;
import com.passpace.dto.collect.CollectDtos.TableCount;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.util.ArrayList;
import java.util.List;

/**
 * [용성] 관리자 화면용 DB 점검: 연결 성공/실패 + 테이블별 행 수 + 비어 있는 테이블 목록.
 * 비밀번호·접속 주소는 화면에 내보내지 않는다 (DB 이름·버전만).
 */
@Component
public class DbStatusChecker {

    private final JdbcTemplate jdbc;

    public DbStatusChecker(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public DbStatus check() {
        long t0 = System.currentTimeMillis();
        DataSource ds = jdbc.getDataSource();
        String version;
        try (Connection c = ds.getConnection()) {
            if (!c.isValid(3)) {
                return fail(t0, "연결은 열렸지만 응답이 없습니다 (isValid 실패)");
            }
            DatabaseMetaData md = c.getMetaData();
            version = md.getDatabaseProductName() + " " + md.getDatabaseProductVersion();
        } catch (Exception e) {
            return fail(t0, rootMessage(e));
        }
        try {
            String db = jdbc.queryForObject("SELECT DATABASE()", String.class);
            List<String> names = jdbc.queryForList(
                    "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME",
                    String.class);
            List<TableCount> tables = new ArrayList<>();
            List<String> empty = new ArrayList<>();
            for (String name : names) {
                if (!name.matches("[A-Za-z0-9_]+")) continue;          // 이름 검증 후에만 쿼리에 넣는다
                Long n = jdbc.queryForObject("SELECT COUNT(*) FROM `" + name + "`", Long.class);
                long rows = n == null ? 0 : n;
                tables.add(new TableCount(name, rows));
                if (rows == 0) empty.add(name);
            }
            return new DbStatus(true, db, version, System.currentTimeMillis() - t0, null, tables.size(), tables, empty);
        } catch (Exception e) {
            return new DbStatus(true, null, version, System.currentTimeMillis() - t0,
                    "연결은 됐지만 테이블 조회 실패: " + rootMessage(e), 0, List.of(), List.of());
        }
    }

    private static DbStatus fail(long t0, String msg) {
        return new DbStatus(false, null, null, System.currentTimeMillis() - t0, msg, 0, List.of(), List.of());
    }

    private static String rootMessage(Throwable e) {
        Throwable t = e;
        while (t.getCause() != null && t.getCause() != t) t = t.getCause();
        return t.getClass().getSimpleName() + ": " + t.getMessage();
    }
}
