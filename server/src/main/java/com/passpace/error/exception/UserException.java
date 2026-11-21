package com.passpace.error.exception;

import com.passpace.error.ErrorCode;

public class UserException extends BaseAppException {
    public UserException(ErrorCode code) { super(code); }
    public UserException(ErrorCode code, String detail) { super(code, detail); }
}
