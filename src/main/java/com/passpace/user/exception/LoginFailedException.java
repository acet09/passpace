package com.passpace.user.exception;

/** [한결] 아이디가 없거나 비밀번호가 틀림 (보안상 어느 쪽인지 구분해서 알려 주지 않는다) */
public class LoginFailedException extends RuntimeException {

    public LoginFailedException() {
        super("아이디 또는 비밀번호가 올바르지 않습니다.");
    }
}
