package com.passpace.error;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * 이 서비스의 모든 오류를 한 곳에 모은 목록.
 * 오류마다 HTTP 상태 코드와 화면에 보여 줄 문장(한국어·영어)을 정해 둔다.
 * 새 오류가 필요하면 여기에 한 줄 추가하고, Service 에서 throw new XxxException(ErrorCode.이름) 한다.
 */
@Getter
@RequiredArgsConstructor
public enum ErrorCode {

    // ── 공통 ──
    INVALID_REQUEST(400, "요청 값이 올바르지 않습니다.", "Invalid request."),
    NOT_FOUND_ENDPOINT(404, "없는 주소입니다.", "Endpoint not found."),
    METHOD_NOT_ALLOWED(405, "허용되지 않은 메서드입니다.", "Method not allowed."),
    DATA_INTEGRITY_VIOLATION(409, "다른 데이터가 사용 중이거나 중복된 값입니다.", "Data integrity violation."),
    SERVER_ERROR(500, "서버 오류가 발생했습니다.", "Server error."),

    // ── 인증·권한 (JWT) ──
    FAILURE_LOGIN(400, "아이디 또는 비밀번호가 맞지 않습니다.", "Invalid login ID or password."),
    DUPLICATED_EMAIL(409, "이미 가입된 이메일입니다.", "Email already exists."),
    NOT_FOUND_USER(404, "사용자를 찾을 수 없습니다.", "User not found."),
    FAILURE_JWT_VERIFIED(401, "로그인이 필요합니다.", "Authentication required."),
    INVALID_JWT(401, "올바르지 않은 토큰입니다.", "Invalid token."),
    JWT_EXPIRED(401, "토큰이 만료되었습니다. 다시 로그인하세요.", "Token expired."),
    PERMISSION_DENIED(403, "권한이 없습니다.", "Permission denied."),
    FORBIDDEN_ACCESS(403, "다른 사용자의 데이터입니다.", "Forbidden access."),

    // ── passpace 공통 ──
    SERVICE_UNAVAILABLE(503, "데이터가 아직 준비되지 않았습니다.", "Service unavailable."),

    // ── 회원 ──
    DUPLICATED_LOGIN_ID(409, "이미 사용 중인 아이디입니다.", "Login ID already exists."),

    // ── 챗봇·학습계획 ── (동건)
    MISSING_MAJOR(400, "전공 구분이 설정되지 않았습니다. 마이페이지에서 전공 여부를 먼저 선택하세요.", "Major type is not set."),
    NOT_FOUND_CONVERSATION(404, "대화방을 찾을 수 없습니다.", "Conversation not found."),
    LLM_UNAVAILABLE(503, "챗봇 서버(Ollama)에 연결할 수 없습니다.", "LLM server unavailable."),

    ;

    private final int status;
    private final String ko;
    private final String en;

    /** 응답 JSON 의 code 칸에 나가는 값 (enum 이름 그대로) */
    public String getCode() {
        return name();
    }
}
