package com.passpace.repository;

import com.passpace.constant.MajorType;
import com.passpace.dto.user.UserViews.UserAccount;
import com.passpace.dto.user.UserViews.UserProfile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Repository;

import java.sql.PreparedStatement;
import java.sql.Statement;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

/**
 * [한결] USERS 테이블 JDBC 구현.
 * ERD 원본에서 created_at 은 DEFAULT 가 없으므로 INSERT 할 때 NOW() 를 직접 넣는다.
 */
@Repository
public class JdbcUserRepository implements UserRepository {

    private final JdbcTemplate jdbc;

    public JdbcUserRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public boolean existsByLoginId(String loginId) {
        String sql = "SELECT COUNT(*) FROM USERS WHERE login_id = ?";

        Long count = jdbc.queryForObject(sql, Long.class, loginId);

        return count != null && count > 0;
    }

    @Override
    public boolean existsByEmail(String email, Long excludeUserId) {
        if (excludeUserId == null) {
            String sql = "SELECT COUNT(*) FROM USERS WHERE email = ?";

            Long count = jdbc.queryForObject(sql, Long.class, email);

            return count != null && count > 0;
        }

        String sql = """
                SELECT COUNT(*)
                FROM USERS
                WHERE email = ?
                  AND user_id <> ?
                """;

        Long count = jdbc.queryForObject(
                sql, Long.class, email, excludeUserId
        );

        return count != null && count > 0;
    }

    @Override
    public Long insert(String loginId, String passwordHash,
                       String nickname, String email, MajorType majorType) {
        String sql = """
                INSERT INTO USERS (
                    login_id, password_hash, nickname,
                    email, major_type, created_at
                )
                VALUES (?, ?, ?, ?, ?, NOW())
                """;

        KeyHolder keyHolder = new GeneratedKeyHolder();

        jdbc.update(connection -> {
            PreparedStatement ps = connection.prepareStatement(
                    sql, Statement.RETURN_GENERATED_KEYS
            );

            ps.setString(1, loginId);
            ps.setString(2, passwordHash);
            ps.setString(3, nickname);
            ps.setString(4, email);
            ps.setString(5, majorType == null ? null : majorType.name());

            return ps;
        }, keyHolder);

        Number key = keyHolder.getKey();

        if (key == null) {
            throw new IllegalStateException("생성된 회원 번호를 가져오지 못했습니다.");
        }

        return key.longValue();
    }

    @Override
    public Optional<UserAccount> findAccountByLoginId(String loginId) {
        String sql = """
                SELECT user_id, login_id, password_hash, nickname, major_type
                FROM USERS
                WHERE login_id = ?
                """;

        List<UserAccount> accounts = jdbc.query(
                sql,
                (rs, rowNum) -> new UserAccount(
                        rs.getLong("user_id"),
                        rs.getString("login_id"),
                        rs.getString("password_hash"),
                        rs.getString("nickname"),
                        MajorType.fromCode(rs.getString("major_type"))
                ),
                loginId
        );

        return accounts.stream().findFirst();
    }

    @Override
    public Optional<UserProfile> findProfile(Long userId) {
        String sql = """
                SELECT user_id, login_id, nickname, email, major_type, created_at
                FROM USERS
                WHERE user_id = ?
                """;

        List<UserProfile> profiles = jdbc.query(
                sql,
                (rs, rowNum) -> new UserProfile(
                        rs.getLong("user_id"),
                        rs.getString("login_id"),
                        rs.getString("nickname"),
                        rs.getString("email"),
                        MajorType.fromCode(rs.getString("major_type")),
                        rs.getObject("created_at", LocalDateTime.class)
                ),
                userId
        );

        return profiles.stream().findFirst();
    }

    @Override
    public void updateProfile(Long userId, String nickname,
                              String email, MajorType majorType) {
        String sql = """
                UPDATE USERS
                SET nickname = ?,
                    email = ?,
                    major_type = ?
                WHERE user_id = ?
                """;

        jdbc.update(
                sql,
                nickname,
                email,
                majorType == null ? null : majorType.name(),
                userId
        );
    }
}