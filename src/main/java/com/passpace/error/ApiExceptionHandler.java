package com.passpace.error;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.Map;

/**
 * [공통] JSON API(@RestController)에서 처리하지 못한 오류를 {"error": "..."} 형태로 돌려준다.
 * 화면(@Controller)의 오류는 Spring 기본 오류 페이지를 그대로 쓴다.
 */
@RestControllerAdvice(annotations = RestController.class)
public class ApiExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, String>> badRequest(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }

    /** 데이터 준비가 안 된 경우 등 (예: seed.sql 미실행) → 원인 메시지를 그대로 보여 준다 */
    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<Map<String, String>> notReady(IllegalStateException e) {
        log.warn("처리 불가: {}", e.getMessage());
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(Map.of("error", e.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, String>> serverError(Exception e) {
        log.error("API 처리 중 오류", e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "서버 처리 중 오류가 발생했습니다: " + e.getClass().getSimpleName()));
    }
}
