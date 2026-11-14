package com.passpace.error;

import lombok.Getter;

/**
 * 실패 응답의 data 부분.
 * { "code": "MISSING_MAJOR", "ko": "전공 구분이 설정되지 않았습니다. …", "en": "Major type is not set.", "detail": null }
 */
@Getter
public class ErrorResponseDto {

    private final String code;
    private final String ko;
    private final String en;
    /** 오류 부가 정보 (없으면 null). 예: 어느 입력칸이 틀렸는지, 계획 계산이 실패한 이유 */
    private final String detail;

    public ErrorResponseDto(ErrorCode errorCode) {
        this(errorCode, null);
    }

    public ErrorResponseDto(ErrorCode errorCode, String detail) {
        this.code = errorCode.getCode();
        this.ko = errorCode.getKo();
        this.en = errorCode.getEn();
        this.detail = detail;
    }
}
