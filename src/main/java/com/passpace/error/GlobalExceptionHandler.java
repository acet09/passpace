package com.passpace.error;

import com.passpace.dto.ResponseDto;
import com.passpace.error.exception.BaseAppException;
import com.passpace.util.ResponseUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

/**
 * Controller·Service 에서 던진 예외를 받아 { "status":"ERROR", "code":..., "data":{...} } 로 바꾼다.
 * 위에서부터 "구체적인 예외 → 넓은 예외" 순서로 둔다. 맨 아래 Exception 은 놓친 모든 예외(500).
 */
@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    /** 우리가 던진 도메인 예외 — ErrorCode 에 적힌 상태 코드로 */
    @ExceptionHandler(BaseAppException.class)
    public ResponseEntity<ResponseDto<ErrorResponseDto>> handleApp(BaseAppException e) {
        log.warn("[AppException] type={}, code={}, detail={}",
                e.getClass().getSimpleName(), e.getErrorCode().name(), e.getDetail());
        return error(e.getErrorCode(), e.getDetail());
    }

    /** @PreAuthorize 등에서 권한이 부족할 때 — 아래 Exception 이 먼저 잡으면 500 이 되므로 따로 둔다 */
    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ResponseDto<ErrorResponseDto>> handleAccessDenied(AccessDeniedException e) {
        log.warn("[AccessDenied] {}", e.getMessage());
        return error(ErrorCode.PERMISSION_DENIED, null);
    }

    /** 잘못된 요청 — 본문 JSON 오류, @Valid 검증 실패, 필수 파라미터 누락, 타입 불일치 */
    @ExceptionHandler({
            HttpMessageNotReadableException.class,
            MethodArgumentNotValidException.class,
            MissingServletRequestParameterException.class,
            MethodArgumentTypeMismatchException.class
    })
    public ResponseEntity<ResponseDto<ErrorResponseDto>> handleBadRequest(Exception e) {
        log.warn("[BadRequest] type={}, msg={}", e.getClass().getSimpleName(), e.getMessage());
        String detail = (e instanceof MethodArgumentNotValidException m && m.getBindingResult().getFieldError() != null)
                ? m.getBindingResult().getFieldError().getField() + ": " + m.getBindingResult().getFieldError().getDefaultMessage()
                : null;
        return error(ErrorCode.INVALID_REQUEST, detail);
    }

    /** DB 제약조건 위반 — FK 로 참조 중인 행 삭제, UNIQUE 중복 등 (클라이언트가 고칠 수 있으니 500 이 아니라 409) */
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ResponseDto<ErrorResponseDto>> handleDataIntegrity(DataIntegrityViolationException e) {
        log.warn("[DataIntegrityViolation] {}", e.getMostSpecificCause().getMessage());
        return error(ErrorCode.DATA_INTEGRITY_VIOLATION, null);
    }

    /** 없는 주소 — 404 */
    @ExceptionHandler(NoResourceFoundException.class)
    public ResponseEntity<ResponseDto<ErrorResponseDto>> handleNotFound(NoResourceFoundException e) {
        log.warn("[NotFound] {}", e.getMessage());
        return error(ErrorCode.NOT_FOUND_ENDPOINT, null);
    }

    /** 주소는 있는데 메서드가 다름 — 405 */
    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ResponseDto<ErrorResponseDto>> handleMethodNotAllowed(HttpRequestMethodNotSupportedException e) {
        log.warn("[MethodNotAllowed] {}", e.getMessage());
        return error(ErrorCode.METHOD_NOT_ALLOWED, null);
    }

    /** [passpace] 서비스 계산 중 잘못된 입력 (예: 계획 과목 누락) — 400, 사유는 detail 로 (기존 ApiExceptionHandler 동작 유지) */
    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ResponseDto<ErrorResponseDto>> handleIllegalArgument(IllegalArgumentException e) {
        log.warn("[IllegalArgument] {}", e.getMessage());
        return error(ErrorCode.INVALID_REQUEST, e.getMessage());
    }

    /** [passpace] 데이터 준비가 안 된 경우 (예: seed.sql 미실행) — 503, 원인은 detail 로 (기존 ApiExceptionHandler 동작 유지) */
    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<ResponseDto<ErrorResponseDto>> handleIllegalState(IllegalStateException e) {
        log.warn("[IllegalState] {}", e.getMessage());
        return error(ErrorCode.SERVICE_UNAVAILABLE, e.getMessage());
    }

    /** 예상하지 못한 오류 — 500. 내부 메시지는 응답에 넣지 않고 로그에만 남긴다 */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ResponseDto<ErrorResponseDto>> handleUnexpected(Exception e) {
        log.error("[UnhandledException]", e);
        return error(ErrorCode.SERVER_ERROR, null);
    }

    private ResponseEntity<ResponseDto<ErrorResponseDto>> error(ErrorCode code, String detail) {
        return ResponseUtil.ERROR(code.getStatus(), new ErrorResponseDto(code, detail));
    }
}
