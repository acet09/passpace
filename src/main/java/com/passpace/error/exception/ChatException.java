package com.passpace.error.exception;

import com.passpace.error.ErrorCode;

/** [동건] 챗봇·학습계획에서 나는 실패 (예: 전공 미설정, 남의 대화방) */
public class ChatException extends BaseAppException {
    public ChatException(ErrorCode code) { super(code); }
    public ChatException(ErrorCode code, String detail) { super(code, detail); }
}
