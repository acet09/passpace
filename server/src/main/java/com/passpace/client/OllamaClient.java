package com.passpace.client;

import com.passpace.error.exception.OllamaUnavailableException;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * [동건] 로컬 LLM(Ollama) 호출 전담. HTTP 만 담당하고 프롬프트 내용·검증은 Service 가 한다.
 *
 * 보내는 요청 (POST {base-url}/api/chat)
 * {
 *   "model": "qwen3.5:4b", "stream": false, "think": false,
 *   "options": {"temperature": 0.2, "num_ctx": 8192},
 *   "format": { ...JSON 스키마... }          ← 구조화 응답이 필요할 때만
 *   "messages": [ {"role":"system","content":"규칙"}, {"role":"user","content":"자료+질문"} ]
 * }
 * LLM 은 DB 를 직접 읽지 못한다. Java 가 DB 에서 꺼낸 값을 content 문자열에 넣어 보낸다.
 */
@Component
public class OllamaClient {

    private static final Logger log = LoggerFactory.getLogger(OllamaClient.class);

    private final RestClient restClient;
    private final String model;
    private final boolean sendThinkFalse;
    private final int numCtx;

    public OllamaClient(@Value("${passpace.ollama.base-url}") String baseUrl,
                        @Value("${passpace.ollama.model}") String model,
                        @Value("${passpace.ollama.send-think-false:true}") boolean sendThinkFalse,
                        @Value("${passpace.ollama.num-ctx:8192}") int numCtx,
                        @Value("${passpace.ollama.timeout-seconds:180}") int timeoutSeconds) {
        HttpClient httpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
        JdkClientHttpRequestFactory factory = new JdkClientHttpRequestFactory(httpClient);
        factory.setReadTimeout(Duration.ofSeconds(timeoutSeconds));   // CPU 로 돌면 오래 걸릴 수 있음
        this.restClient = RestClient.builder().baseUrl(baseUrl).requestFactory(factory).build();
        this.model = model;
        this.sendThinkFalse = sendThinkFalse;
        this.numCtx = numCtx;
    }

    public String getModel() {
        return model;
    }

    /**
     * @param systemPrompt 규칙
     * @param userContent  자료 + 질문 (사람이 읽는 텍스트)
     * @param jsonSchema   응답을 JSON 으로 강제할 때 스키마, 자유 문장이면 null
     * @param temperature  0 이면 같은 입력에 같은 답 (분류·추출), 0.2~0.3 은 문장 생성
     * @return 모델 답변 문자열 (message.content)
     */
    @SuppressWarnings("unchecked")
    public String chat(String systemPrompt, String userContent, Map<String, Object> jsonSchema, double temperature) {
        long started = System.currentTimeMillis();
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("model", model);
        body.put("stream", false);
        if (sendThinkFalse) body.put("think", false);
        body.put("options", Map.of("temperature", temperature, "num_ctx", numCtx));
        if (jsonSchema != null) body.put("format", jsonSchema);
        body.put("messages", List.of(
                Map.of("role", "system", "content", systemPrompt),
                Map.of("role", "user", "content", userContent)));
        try {
            Map<String, Object> response = restClient.post().uri("/api/chat")
                    .contentType(MediaType.APPLICATION_JSON).body(body).retrieve().body(Map.class);
            Object message = response == null ? null : response.get("message");
            Object content = message instanceof Map<?, ?> map ? map.get("content") : null;
            if (!(content instanceof String answer) || answer.isBlank())
                throw new OllamaUnavailableException("LLM 응답이 비어 있음 - think 설정 확인", null);
            log.info("Ollama 응답 완료: model={}, elapsedMs={}", model, System.currentTimeMillis() - started);
            return answer.strip();
        } catch (OllamaUnavailableException e) {
            throw e;
        } catch (RestClientResponseException e) {
            String reason = switch (e.getStatusCode().value()) {
                case 404 -> "모델 '" + model + "' 없음 - ollama pull 또는 모델 이름 확인";
                case 400 -> "요청 형식 오류 - think 를 지원하지 않는 모델이면 send-think-false: false";
                default -> "Ollama HTTP 오류 (" + e.getStatusCode().value() + ")";
            };
            throw new OllamaUnavailableException(reason, e);
        } catch (ResourceAccessException e) {
            String detail = String.valueOf(e.getMessage()).toLowerCase();
            String reason = detail.contains("timed out") || detail.contains("timeout")
                    ? "LLM 응답 시간 초과 - GPU 사용 여부·모델 크기 확인"
                    : "Ollama 서버에 연결할 수 없음 - ollama serve 실행 확인";
            throw new OllamaUnavailableException(reason, e);
        } catch (RestClientException e) {
            throw new OllamaUnavailableException("Ollama 요청 실패 - 서버 상태 확인", e);
        }

    }
}
