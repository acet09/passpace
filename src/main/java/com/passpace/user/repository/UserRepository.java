package com.passpace.user.repository;

import com.passpace.common.code.MajorType;
import com.passpace.user.dto.UserViews.UserAccount;
import com.passpace.user.dto.UserViews.UserProfile;

import java.util.Optional;

/** [한결] USERS 테이블 접근. Service 는 이 인터페이스만 안다. */
public interface UserRepository {

    boolean existsByLoginId(String loginId);

    /** @param excludeUserId 본인 수정 시 본인은 제외 (가입 시 null) */
    boolean existsByEmail(String email, Long excludeUserId);

    /** @return 새 user_id */
    Long insert(String loginId, String passwordHash, String nickname, String email, MajorType majorType);

    Optional<UserAccount> findAccountByLoginId(String loginId);

    Optional<UserProfile> findProfile(Long userId);

    void updateProfile(Long userId, String nickname, String email, MajorType majorType);
}
