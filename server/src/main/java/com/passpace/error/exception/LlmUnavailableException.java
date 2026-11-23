package com.passpace.error.exception;

/** [동건] 외부 LLM(Claude API)을 쓸 수 없거나(키 없음·연결 실패·한도 초과) 응답이 비었을 때 */
public class LlmUnavailableException extends RuntimeException {

    public LlmUnavailableException(String message, Throwable cause) {
        super(message, cause);
    }
}
