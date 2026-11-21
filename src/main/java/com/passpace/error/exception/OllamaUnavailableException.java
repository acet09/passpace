package com.passpace.error.exception;

/** [동건] Ollama 에 연결할 수 없거나(꺼짐·모델 없음·시간 초과) 응답이 비었을 때 */
public class OllamaUnavailableException extends RuntimeException {

    public OllamaUnavailableException(String message, Throwable cause) {
        super(message, cause);
    }
}
