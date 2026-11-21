package com.passpace.error.exception;

import com.passpace.error.ErrorCode;

public class AuthException extends BaseAppException {
    public AuthException(ErrorCode code) { super(code); }
    public AuthException(ErrorCode code, String detail) { super(code, detail); }
}
