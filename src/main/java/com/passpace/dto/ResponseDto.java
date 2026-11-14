package com.passpace.dto;

import com.passpace.constant.ResponseStatus;
import lombok.Getter;

/**
 * 모든 API 응답의 바깥 모양.
 * { "status": "SUCCESS", "code": 200, "data": ... }
 * 프론트는 status·code 를 먼저 보고, 실제 내용은 data 에서 꺼낸다.
 */
@Getter
public class ResponseDto<T> {
    private final ResponseStatus status;
    private final int code;
    private T data;

    public ResponseDto(ResponseStatus status, int code, T data) {
        this.status = status;
        this.code = code;
        this.data = data;
    }

    public ResponseDto(ResponseStatus status, int code) {
        this.status = status;
        this.code = code;
    }
}
