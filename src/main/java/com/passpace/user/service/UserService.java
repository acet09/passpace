package com.passpace.user.service;

import com.passpace.common.LoginUser;
import com.passpace.user.dto.ProfileForm;
import com.passpace.user.dto.SignUpForm;
import com.passpace.user.dto.UserViews.UserProfile;

/** [한결] 회원 기능. Controller 는 이 인터페이스만 안다. */
public interface UserService {

    /**
     * 회원가입.
     * @return 가입 직후 로그인 상태로 쓸 LoginUser
     * @throws com.passpace.user.exception.DuplicateUserException 아이디·이메일 중복
     */
    LoginUser signUp(SignUpForm form);

    /** @throws com.passpace.user.exception.LoginFailedException 아이디 없음 또는 비밀번호 불일치 */
    LoginUser login(String loginId, String rawPassword);

    UserProfile getProfile(Long userId);

    /** @return 수정된 정보가 반영된 LoginUser (세션 갱신용) */
    LoginUser updateProfile(Long userId, ProfileForm form);
}
