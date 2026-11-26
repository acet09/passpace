package com.passpace.user.withdrawal;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.util.Optional;

/** [한결] Service의 회원 행 잠금·트랜잭션 안에서 본인의 데이터만 실제 삭제한다. */
@Repository
public class AccountWithdrawalRepository {
    public static final String WITHDRAWN_PREFIX = "~withdrawn:";
    private final JdbcTemplate jdbc;

    public AccountWithdrawalRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public record Member(long userId, String loginId, String passwordHash, String majorCode) {
        @Override
        public String toString() { return "WithdrawalMember[redacted]"; }
    }

    public static boolean isWithdrawn(String loginId) {
        return loginId != null && loginId.startsWith(WITHDRAWN_PREFIX);
    }

    public static String withdrawnLoginId(long userId) {
        if (userId <= 0) throw new IllegalArgumentException("올바른 회원 번호가 필요합니다.");
        return WITHDRAWN_PREFIX + userId;
    }

    public Optional<Member> lockMember(long userId) {
        return jdbc.query("""
                SELECT user_id, login_id, password_hash, major_type
                FROM USERS WHERE user_id = ? FOR UPDATE
                """, (rs, index) -> new Member(rs.getLong("user_id"), rs.getString("login_id"),
                rs.getString("password_hash"), rs.getString("major_type")), userId).stream().findFirst();
    }

    public boolean isCurrentIdentity(Long userId, String loginId) {
        if (userId == null || userId <= 0 || loginId == null || isWithdrawn(loginId)) return false;
        Integer count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM USERS
                WHERE user_id = ? AND login_id = ? AND login_id NOT LIKE '~withdrawn:%'
                """, Integer.class, userId, loginId);
        return count != null && count == 1;
    }

    public int withdraw(long userId, String expectedLoginId) {
        if (!TransactionSynchronizationManager.isActualTransactionActive()) {
            throw new IllegalStateException("회원탈퇴 삭제에는 Service 트랜잭션이 필요합니다.");
        }
        // Lock parents before deleting children so concurrent FK inserts wait.
        for (String sql : new String[]{
                "SELECT goal_id FROM USER_GOALS WHERE user_id = ? ORDER BY goal_id FOR UPDATE",
                "SELECT plan_id FROM STUDY_PLANS WHERE user_id = ? ORDER BY plan_id FOR UPDATE",
                "SELECT task_id FROM STUDY_PLAN_DETAILS WHERE user_id = ? ORDER BY task_id FOR UPDATE",
                "SELECT con_id FROM CHAT_CONVERSATIONS WHERE user_id = ? ORDER BY con_id FOR UPDATE"}) {
            jdbc.query(sql, (RowCallbackHandler) ignored -> { }, userId);
        }
        jdbc.update("DELETE FROM AI_PLAN_PROPOSALS WHERE user_id = ?", userId);
        jdbc.update("DELETE FROM STUDY_SESSIONS WHERE user_id = ?", userId);
        jdbc.update("DELETE FROM STUDY_PLAN_DETAILS WHERE user_id = ?", userId);
        // Both ends must be this member's; inconsistent foreign ownership is not erased.
        jdbc.update("""
                DELETE FROM PLAN_GOALS
                WHERE plan_id IN (SELECT plan_id FROM STUDY_PLANS WHERE user_id = ?)
                  AND goal_id IN (SELECT goal_id FROM USER_GOALS WHERE user_id = ?)
                """, userId, userId);
        jdbc.update("""
                DELETE FROM GOAL_SUBJECTS
                WHERE goal_id IN (SELECT goal_id FROM USER_GOALS WHERE user_id = ?)
                """, userId);
        jdbc.update("""
                DELETE FROM CHAT_MESSAGES
                WHERE con_id IN (SELECT con_id FROM CHAT_CONVERSATIONS WHERE user_id = ?)
                """, userId);
        jdbc.update("DELETE FROM CHAT_CONVERSATIONS WHERE user_id = ?", userId);
        jdbc.update("DELETE FROM STUDY_PLANS WHERE user_id = ?", userId);
        jdbc.update("DELETE FROM USER_GOALS WHERE user_id = ?", userId);
        return jdbc.update("""
                DELETE FROM USERS
                WHERE user_id = ? AND login_id = ? AND login_id NOT LIKE '~withdrawn:%'
                """, userId, expectedLoginId);
    }
}
