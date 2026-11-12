package com.passpace.error.exception;

/** [한결] 아이디 또는 이메일 중복 */
public class DuplicateUserException extends RuntimeException {

    /** 오류를 표시할 입력칸 이름 (loginId / email) */
    private final String field;

    public DuplicateUserException(String field, String message) {
        super(message);
        this.field = field;
    }

    public String getField() {
        return field;
    }
}
