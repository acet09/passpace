package com.passpace.study;

import com.fasterxml.jackson.annotation.JsonAnySetter;
import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.JsonToken;
import com.fasterxml.jackson.databind.DeserializationContext;
import com.fasterxml.jackson.databind.JsonMappingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
import com.fasterxml.jackson.databind.deser.std.StdDeserializer;
import com.passpace.error.ErrorCode;
import com.passpace.error.exception.BaseAppException;
import io.swagger.v3.oas.annotations.media.Schema;

import java.io.IOException;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.List;

/**
 * [한결] 학습기록 API 계약. 모든 시간은 실제 공부한 정수 분이며 날짜는 Asia/Seoul 기준이다.
 *
 * <p>POST /study/sessions는 수동 기록을 새로 생성한다. 날짜와 1~1440분이 필수다.
 * 계획에 연결하려면 taskId와 expectedPlanVersion을 함께 보낸다.
 * subjectId/planId는 연결 일치 확인용이며 taskId 없이 독립 저장하지 않는다.
 * 입력에 없는 시작/종료 시각을 만들거나 계획·이해도·완료 상태를 수정하지 않는다.
 * 같은 POST를 다시 보내면 별도 기록이므로, 응답 유실 시 자동 재전송으로 중복을 막는
 * 영속적 idempotency 보장은 이 계약에 없다.
 *
 * <p>GET /study/sessions는 startDate/endDate를 모두 포함하고 최대 366일을 조회한다.
 * page는 0~10000, pageSize는 1~100(기본 20)이며 날짜 DESC, sessionId DESC 순이다.
 * 응답 data는 items/page/pageSize/hasNext를 가진 객체다.
 *
 * <p>PATCH /study/sessions/{sessionId}는 본인의 MANUAL 기록 날짜와 분만 수정한다.
 * studyDate/durationMinutes 및 조회한 expectedStudyDate/expectedDurationMinutes가 필수다.
 * 기존 값과 다르면409이며 별도 version 컬럼을 추가하지 않는다. 계획 연결과 다른 이력은 유지한다.
 *
 * <p>GET /dashboard/study-stats의 period는 LAST_7_DAYS(기본), LAST_30_DAYS, CUSTOM이다.
 * 최근 기간은 서울 기준 오늘을 포함하며 startDate/endDate를 동시에 지정할 수 없다.
 * CUSTOM은 두 날짜가 필수다. 일별 목록은 날짜 ASC, 빈 날짜는 기록된 시간 0분이다.
 * completionRate는 계산 근거가 확정되지 않아 항상 null이다.
 *
 * <p>성공은 기존 {status:SUCCESS, code:200, data:...}, 오류도 기존 JSON 형태를 사용한다.
 * 현재 DB의 과목 ID가 없는 계획 항목은 subjectId=null과 저장된 이름으로 표현한다.
 */
public final class StudyDtos {
    private StudyDtos() { }

    public record SaveSessionRequest(
            @Schema(description = "실제 공부한 서울 날짜, YYYY-MM-DD")
            @JsonDeserialize(using = StrictDateDeserializer.class) LocalDate studyDate,
            @Schema(description = "실제 공부한 정수 분, 1~1440")
            @JsonDeserialize(using = StrictIntegerDeserializer.class) Integer durationMinutes,
            @Schema(description = "본인의 날짜별 계획 항목 ID, 미연결 수동 기록은 생략")
            @JsonDeserialize(using = StrictLongDeserializer.class) Long taskId,
            @Schema(description = "선택한 계획 버전. taskId 지정 시 필수")
            @JsonDeserialize(using = StrictIntegerDeserializer.class) Integer expectedPlanVersion,
            @Schema(description = "taskId 지정 시 일치 여부를 확인하는 선택 과목 ID")
            @JsonDeserialize(using = StrictLongDeserializer.class) Long subjectId,
            @Schema(description = "taskId 지정 시 일치 여부를 확인하는 선택 계획 ID")
            @JsonDeserialize(using = StrictLongDeserializer.class) Long planId) {

        @JsonAnySetter
        public void rejectUnknown(String name, JsonNode ignored) {
            throw new IllegalArgumentException("지원하지 않는 학습기록 입력 항목입니다.");
        }
    }

    public record UpdateSessionRequest(
            @Schema(description = "수정할 실제 공부 날짜, 한국 기준 오늘 이하 YYYY-MM-DD")
            @JsonDeserialize(using = StrictDateDeserializer.class) LocalDate studyDate,
            @Schema(description = "수정할 실제 정수 분, 1~1440")
            @JsonDeserialize(using = StrictIntegerDeserializer.class) Integer durationMinutes,
            @Schema(description = "목록을 조회했을 때의 원래 날짜, 충돌 확인용")
            @JsonDeserialize(using = StrictDateDeserializer.class) LocalDate expectedStudyDate,
            @Schema(description = "목록을 조회했을 때의 원래 정수 분, 충돌 확인용")
            @JsonDeserialize(using = StrictIntegerDeserializer.class) Integer expectedDurationMinutes,
            @Schema(description = "생략하면 기존 연결 유지. 객체이면 본인 계획 항목으로 연결하거나 null taskId로 해제")
            TaskLinkChange taskLink,
            @Schema(description = "새 앱의 기존 연결 확인. 객체 안 taskId=null은 미연결을 뜻하며 객체 생략은 구형 요청과 호환")
            TaskLinkSnapshot expectedTask) {
        @JsonAnySetter
        public void rejectUnknown(String name, JsonNode ignored) {
            throw new IllegalArgumentException("지원하지 않는 학습기록 수정 항목입니다.");
        }
    }

    public record TaskLinkChange(
            @JsonDeserialize(using = StrictLongDeserializer.class) Long taskId,
            @JsonDeserialize(using = StrictIntegerDeserializer.class) Integer expectedPlanVersion,
            @JsonDeserialize(using = StrictLongDeserializer.class) Long expectedTaskId) {
        @JsonAnySetter public void rejectUnknown(String name, JsonNode ignored) {
            throw new IllegalArgumentException("지원하지 않는 과목 연결 항목입니다.");
        }
    }

    public record TaskLinkSnapshot(@JsonDeserialize(using = StrictLongDeserializer.class) Long taskId) {
        @JsonAnySetter public void rejectUnknown(String name, JsonNode ignored) {
            throw new IllegalArgumentException("지원하지 않는 기존 연결 확인 항목입니다.");
        }
    }

    public record DeleteSessionRequest(
            @JsonDeserialize(using = StrictDateDeserializer.class) LocalDate expectedStudyDate,
            @JsonDeserialize(using = StrictIntegerDeserializer.class) Integer expectedDurationMinutes,
            @Schema(description = "조회한 기존 taskId. null 또는 생략은 미연결 기록을 의미")
            @JsonDeserialize(using = StrictLongDeserializer.class) Long expectedTaskId) {
        @JsonAnySetter public void rejectUnknown(String name, JsonNode ignored) {
            throw new IllegalArgumentException("지원하지 않는 삭제 확인 항목입니다.");
        }
    }

    public record DeleteSessionResponse(long sessionId, boolean deleted) { }

    public record PlanTaskChoice(long taskId, long planId, String planName, int planVersion,
                                 Long subjectId, String subjectName, String certificationName,
                                 @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd") LocalDate scheduledDate,
                                 String planStatus) { }

    public record PlanTaskPageResponse(List<PlanTaskChoice> items, int page, int pageSize, boolean hasNext) {
        public PlanTaskPageResponse { items = List.copyOf(items); }
    }

    public record SessionResponse(long sessionId,
                                  @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd")
                                  LocalDate studyDate, int durationMinutes,
                                  Long taskId, Long planId, Long subjectId,
                                  String subjectName, String inputMethod) { }

    public record SessionPageResponse(List<SessionResponse> items, int page, int pageSize,
                                      boolean hasNext) {
        public SessionPageResponse {
            items = List.copyOf(items);
        }
    }

    public record DailyStudyMinutes(
            @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd") LocalDate studyDate,
            long durationMinutes) { }

    public record StudyStatsResponse(String period,
                                     @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd")
                                     LocalDate startDate,
                                     @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd")
                                     LocalDate endDate,
                                     String timezone, long totalMinutes,
                                     List<DailyStudyMinutes> dailyStudyMinutes,
                                     @Schema(description = "진도 기준 미확정으로 항상 null", nullable = true)
                                     Double completionRate) {
        public StudyStatsResponse {
            dailyStudyMinutes = List.copyOf(dailyStudyMinutes);
        }
    }

    // 저장소 내부 조회 결과. API에 사용자/권한 확인용 내부 값을 노출하지 않는다.
    public record UserState(String majorCode) { }
    public record PlanTask(long taskId, long planId, Long subjectId, String subjectName,
                           Integer planVersion, String planStatus) { }
    public record SessionRow(long sessionId, LocalDate studyDate, Integer durationMinutes,
                             Long taskId, Long planId, Long subjectId, String subjectName,
                             String inputMethod, boolean invalidLink) { }
    public record DayTotal(LocalDate studyDate, long durationMinutes, long invalidRecords) { }

    public static final class StudyException extends BaseAppException {
        public StudyException(ErrorCode code, String detail) {
            super(code, detail);
        }
    }

    /** 이 API에서 소수·문자열·불리언을 정수로 묵시 변환하지 않는다. */
    public static final class StrictIntegerDeserializer extends StdDeserializer<Integer> {
        public StrictIntegerDeserializer() { super(Integer.class); }
        @Override
        public Integer deserialize(JsonParser p, DeserializationContext context) throws IOException {
            if (!p.hasToken(JsonToken.VALUE_NUMBER_INT))
                throw JsonMappingException.from(p, "정수형 JSON 숫자로 입력해 주세요.");
            return p.getIntValue();
        }
    }

    public static final class StrictLongDeserializer extends StdDeserializer<Long> {
        public StrictLongDeserializer() { super(Long.class); }
        @Override
        public Long deserialize(JsonParser p, DeserializationContext context) throws IOException {
            if (!p.hasToken(JsonToken.VALUE_NUMBER_INT))
                throw JsonMappingException.from(p, "식별자는 정수형 JSON 숫자로 입력해 주세요.");
            return p.getLongValue();
        }
    }

    public static final class StrictDateDeserializer extends StdDeserializer<LocalDate> {
        public StrictDateDeserializer() { super(LocalDate.class); }
        @Override
        public LocalDate deserialize(JsonParser p, DeserializationContext context) throws IOException {
            if (!p.hasToken(JsonToken.VALUE_STRING) || !p.getText().matches("\\d{4}-\\d{2}-\\d{2}"))
                throw JsonMappingException.from(p, "날짜는 YYYY-MM-DD 문자열로 입력해 주세요.");
            try {
                return LocalDate.parse(p.getText());
            } catch (DateTimeParseException e) {
                throw JsonMappingException.from(p, "존재하는 날짜를 입력해 주세요.");
            }
        }
    }
}
