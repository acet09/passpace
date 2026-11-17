package com.passpace.error.exception;

import com.passpace.error.ErrorCode;

public class JwtException extends BaseAppException {
    public JwtException(ErrorCode code) { super(code); }
    public JwtException(ErrorCode code, String detail) { super(code, detail); }
}
