package com.passpace.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Repository;

import java.sql.PreparedStatement;
import java.sql.Statement;

/** [용성] DATA_SYNC_JOBS JDBC 구현 */
@Repository
public class JdbcSyncJobRepository implements SyncJobRepository {

    private final JdbcTemplate jdbc;

    public JdbcSyncJobRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public long start(long sourceId, String syncTarget) {
        KeyHolder key = new GeneratedKeyHolder();
        jdbc.update(con -> {
            PreparedStatement ps = con.prepareStatement(
                    "INSERT INTO DATA_SYNC_JOBS (source_id, sync_target, started_at, status) VALUES (?, ?, NOW(), 'RUNNING')",
                    Statement.RETURN_GENERATED_KEYS);
            ps.setLong(1, sourceId);
            ps.setString(2, syncTarget);
            return ps;
        }, key);
        return key.getKey().longValue();
    }

    @Override
    public void finish(long syncLogId, int success, int failed, int skipped, String status, String failType, String errorMessage) {
        jdbc.update("""
                UPDATE DATA_SYNC_JOBS SET ended_at = NOW(), success_count = ?, failed_count = ?, skipped_count = ?,
                       status = ?, fail_type = ?, error_message = ?
                WHERE sync_log_id = ?
                """, success, failed, skipped, status, failType, errorMessage, syncLogId);
    }
}
