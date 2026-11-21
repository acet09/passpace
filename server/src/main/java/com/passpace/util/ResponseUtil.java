package com.passpace.util;

import com.passpace.constant.ResponseStatus;
import com.passpace.dto.ResponseDto;
import org.springframework.http.ResponseEntity;

/**
 * 응답을 만드는 도구. Controller 는 return ResponseUtil.SUCCESS(데이터); 한 줄로 끝낸다.
 * 모든 API 가 이 도구로 응답하므로 응답 모양 {status, code, data} 가 하나로 유지된다.
 */
public final class ResponseUtil {

    private ResponseUtil() {
    }

    /** 200 + data 없음 (수정·삭제 성공) */
    public static ResponseEntity<ResponseDto<Void>> SUCCESS() {
        return ResponseEntity.ok(
                new ResponseDto<>(ResponseStatus.SUCCESS, 200));
    }

    /** 200 + data */
    public static <T> ResponseEntity<ResponseDto<T>> SUCCESS(T data) {
        return ResponseEntity.ok(
                new ResponseDto<>(ResponseStatus.SUCCESS, 200, data));
    }

    /** 실패: HTTP 상태 코드와 응답 본문의 code 를 같게 맞춘다 */
    public static <T> ResponseEntity<ResponseDto<T>> ERROR(int status, T data) {
        return ResponseEntity.status(status)
                .body(new ResponseDto<>(ResponseStatus.ERROR, status, data));
    }
}
