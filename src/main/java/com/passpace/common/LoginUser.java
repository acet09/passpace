package com.passpace.common;

import com.passpace.common.code.MajorType;

import java.io.Serializable;

/**
 * [공통 계약] 로그인한 사용자 정보. 세션({@link SessionConst#LOGIN_USER})에 저장된다.
 *
 * @param userId    USERS.user_id
 * @param loginId   USERS.login_id (확장 컬럼)
 * @param nickname  USERS.nickname
 * @param majorType USERS.major_type (모르면 null)
 */
public record LoginUser(Long userId, String loginId, String nickname, MajorType majorType) implements Serializable {
}
