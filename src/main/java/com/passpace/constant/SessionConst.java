package com.passpace.constant;

import com.passpace.auth.LoginUser;

/**
 * [공통 계약] 세션 속성 이름.
 * 한결(로그인)이 이 이름으로 저장하고, 동건(챗봇)이 같은 이름으로 꺼내 쓴다.
 */
public final class SessionConst {

    /** 값의 타입: {@link LoginUser} */
    public static final String LOGIN_USER = "loginUser";

    private SessionConst() {
    }
}
