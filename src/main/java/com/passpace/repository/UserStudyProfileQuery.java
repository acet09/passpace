package com.passpace.repository;

import com.passpace.domain.UserStudyProfile;

import java.util.Optional;

/**
 * [공통 계약] 사용자 학습 조건 조회. 한결이 구현(user.query.JdbcUserStudyProfileQuery), 동건이 사용.
 */
public interface UserStudyProfileQuery {

    Optional<UserStudyProfile> findByUserId(Long userId);
}
