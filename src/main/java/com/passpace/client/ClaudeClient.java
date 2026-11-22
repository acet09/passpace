package com.passpace.client;

import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.anthropic.core.JsonValue;
import com.anthropic.errors.AnthropicIoException;
import com.anthropic.errors.AnthropicServiceException;
import com.anthropic.errors.NotFoundException;
import com.anthropic.errors.PermissionDeniedException;
import com.anthropic.errors.RateLimitException;
import com.anthropic.errors.UnauthorizedException;
import com.anthropic.models.messages.JsonOutputFormat;
import com.anthropic.models.messages.Message;
import com.anthropic.models.messages.MessageCreateParams;
import com.anthropic.models.messages.OutputConfig;
import com.anthropic.models.messages.StopReason;
import com.passpace.error.exception.LlmUnavailableException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * [동건] 외부 LLM(Claude API) 호출 전담. 예전 로컬 LLM(Ollama) 호출을 대신한다.
 * HTTP 호출만 담당하고 프롬프트 내용·숫자 검증은 Service 가 한다.
 *
 * - 공식 Java SDK(com.anthropic:anthropic-java)로 Messages API 를 호출한다
 * - API 키: 환경변수 ANTHROPIC_API_KEY 또는 application-local.yml 의 passpace.claude.api-key (저장소에 올리지 않음)
 * - 키가 없거나 호출이 실패하면 LlmUnavailableException → 챗봇은 Java 기본 안내로 답한다 (멈추지 않음)
 * - LLM 은 DB 를 직접 읽지 못한다. Java 가 DB 에서 꺼낸 값을 userContent 문자열에 넣어 보낸다
 */
@Component
public class ClaudeClient {

    private static final Logger log = LoggerFactory.getLogger(ClaudeClient.class);

    private final AnthropicClient client;   // 키가 없으면 null
    private final String model;
    private final OutputConfig.Effort effort;
    private final long maxTokens;

    public ClaudeClient(@Value("${passpace.claude.api-key:}") String apiKey,
                        @Value("${passpace.claude.model:claude-opus-5-5}") String model,
                        @Value("${passpace.claude.effort:low}") String effort,
                        @Value("${passpace.claude.max-tokens:16000}") long maxTokens,
                        @Value("${passpace.claude.timeout-seconds:120}") int timeoutSeconds) {
        this.model = model;
        this.effort = OutputConfig.Effort.of(effort == null || effort.isBlank() ? "low" : effort.trim().toLowerCase());
        this.maxTokens = maxTokens;
        if (apiKey == null || apiKey.isBlank()) {
            this.client = null;
            log.warn("Claude API 키가 없습니다. 챗봇은 Java 기본 안내로 답합니다 "
                    + "(환경변수 ANTHROPIC_API_KEY 또는 application-local.yml 의 passpace.claude.api-key).");
        } else {
            this.client = AnthropicOkHttpClient.builder()
                    .apiKey(apiKey.trim())
                    .timeout(Duration.ofSeconds(timeoutSeconds))
                    .build();
        }
    }

    public String getModel() {
        return model;
    }

    /**
     * @param systemPrompt 규칙
     * @param userContent  자료 + 질문 (사람이 읽는 텍스트)
     * @param jsonSchema   응답을 JSON 으로 강제할 때 스키마(additionalProperties: false 포함), 자유 문장이면 null
     * @return 모델 답변 문자열
     */
    public String chat(String systemPrompt, String userContent, Map<String, Object> jsonSchema) {
        if (client == null)
            throw new LlmUnavailableException("Claude API 키 없음 - ANTHROPIC_API_KEY 설정 확인", null);
        long started = System.currentTimeMillis();
        OutputConfig.Builder output = OutputConfig.builder().effort(effort);
        if (jsonSchema != null) {
            JsonOutputFormat.Schema.Builder schema = JsonOutputFormat.Schema.builder();
            jsonSchema.forEach((key, value) -> schema.putAdditionalProperty(key, JsonValue.from(value)));
            output.format(JsonOutputFormat.builder().schema(schema.build()).build());
        }
        MessageCreateParams params = MessageCreateParams.builder()
                .model(model)
                .maxTokens(maxTokens)
                .system(systemPrompt)
                .outputConfig(output.build())
                .addUserMessage(userContent)
                .build();
        try {
            Message response = client.messages().create(params);
            String stop = response.stopReason().map(Object::toString).orElse("");
            if (response.stopReason().filter(StopReason.REFUSAL::equals).isPresent())
                throw new LlmUnavailableException("LLM 이 이 요청에 답하지 않음(refusal)", null);
            String answer = response.content().stream()
                    .flatMap(block -> block.text().stream())
                    .map(text -> text.text())
                    .collect(Collectors.joining());
            if (answer.isBlank())
                throw new LlmUnavailableException("LLM 응답이 비어 있음 (stop_reason=" + stop + ")", null);
            log.info("Claude 응답 완료: model={}, elapsedMs={}, in={}, out={}", model,
                    System.currentTimeMillis() - started, response.usage().inputTokens(), response.usage().outputTokens());
            return answer.strip();
        } catch (LlmUnavailableException e) {
            throw e;
        } catch (UnauthorizedException | PermissionDeniedException e) {
            throw new LlmUnavailableException("Claude API 키가 올바르지 않거나 권한 없음 - 키 확인", e);
        } catch (NotFoundException e) {
            throw new LlmUnavailableException("모델 '" + model + "' 없음 - passpace.claude.model 확인", e);
        } catch (RateLimitException e) {
            throw new LlmUnavailableException("Claude API 요청 한도 초과 - 잠시 후 다시 시도", e);
        } catch (AnthropicServiceException e) {
            throw new LlmUnavailableException("Claude API 오류 (" + e.statusCode() + ") - 크레딧·요청 형식 확인", e);
        } catch (AnthropicIoException e) {
            throw new LlmUnavailableException("Claude API 에 연결할 수 없음 - 네트워크·시간 초과 확인", e);
        } catch (RuntimeException e) {
            throw new LlmUnavailableException("Claude API 요청 실패", e);
        }
    }
}
