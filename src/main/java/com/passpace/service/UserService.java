package com.passpace.service;

import com.passpace.dto.user.UpdateUserRequestDto;
import com.passpace.dto.user.UserViews.UserProfile;

/**
 * [한결] 마이페이지 회원정보. Controller 는 이 인터페이스만 안다.
 * [JWT] 회원가입·로그인은 AuthService 로 옮겼다 (토큰 발급과 같이 있어야 해서).
 */
public interface UserService {

    /** @throws com.passpace.error.exception.UserException NOT_FOUND_USER */
    UserProfile getProfile(Long userId);

    /** @throws com.passpace.error.exception.UserException DUPLICATED_EMAIL (다른 회원이 쓰는 이메일) */
    void updateProfile(Long userId, UpdateUserRequestDto request);
}
