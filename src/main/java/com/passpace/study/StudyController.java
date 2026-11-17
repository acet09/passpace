package com.passpace.study;

import com.passpace.dto.ResponseDto;
import com.passpace.error.ErrorCode;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.study.StudyDtos.SaveSessionRequest;
import com.passpace.study.StudyDtos.SessionPageResponse;
import com.passpace.study.StudyDtos.SessionResponse;
import com.passpace.study.StudyDtos.StudyException;
import com.passpace.study.StudyDtos.StudyStatsResponse;
import com.passpace.study.StudyDtos.UpdateSessionRequest;
import com.passpace.study.StudyDtos.DeleteSessionRequest;
import com.passpace.study.StudyDtos.DeleteSessionResponse;
import com.passpace.study.StudyDtos.PlanTaskPageResponse;
import com.passpace.util.ResponseUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.time.format.DateTimeParseException;

/** [한결] 학습기록·실제 공부시간 통계. 기존 JWT 인증·JSON 응답 규칙을 재사용한다. */
@RestController
@Tag(name = "학습기록과 개인 통계", description = "수동 공부시간 저장·조회 및 실제 공부시간 집계")
public class StudyController {
    private final StudyService service;

    public StudyController(StudyService service) {
        this.service = service;
    }

    @PostMapping("/study/sessions")
    @Operation(summary = "공부시간 수동 기록 저장", description =
            "studyDate와 실제 정수 durationMinutes를 저장합니다. 계획 연결 시 taskId와 " +
            "expectedPlanVersion이 필요합니다. 시작·종료 시각과 학습 완료율은 생성하지 않습니다. " +
            "같은 요청의 자동 재전송을 중복 제거하는 API는 아닙니다.")
    public ResponseEntity<ResponseDto<SessionResponse>> save(
            @AuthenticationPrincipal JwtPrincipal principal,
            @RequestBody SaveSessionRequest request) {
        JwtPrincipal user = requirePrincipal(principal);
        return ResponseUtil.SUCCESS(service.save(user.getUserId(), user.getMajorType(), request));
    }

    @PatchMapping("/study/sessions/{sessionId}")
    @Operation(summary = "본인의 직접 입력 공부기록 수정", description =
            "studyDate/durationMinutes와 조회 당시 expectedStudyDate/expectedDurationMinutes가 필수입니다. " +
            "taskLink 생략 시 기존 연결 유지, 지정 시 본인 항목/버전과 기존 연결을 확인합니다. 오래된 값은409입니다.")
    public ResponseEntity<ResponseDto<SessionResponse>> update(
            @AuthenticationPrincipal JwtPrincipal principal,
            @PathVariable long sessionId,
            @RequestBody UpdateSessionRequest request) {
        JwtPrincipal user = requirePrincipal(principal);
        return ResponseUtil.SUCCESS(service.update(user.getUserId(), user.getMajorType(), sessionId, request));
    }

    @DeleteMapping("/study/sessions/{sessionId}")
    @Operation(summary = "본인의 직접 입력 공부기록 삭제", description =
            "조회한 expectedStudyDate/expectedDurationMinutes/expectedTaskId를 확인합니다. 다른 계획·과목은 삭제하지 않습니다.")
    public ResponseEntity<ResponseDto<DeleteSessionResponse>> delete(
            @AuthenticationPrincipal JwtPrincipal principal,
            @PathVariable long sessionId, @RequestBody DeleteSessionRequest request) {
        JwtPrincipal user = requirePrincipal(principal);
        return ResponseUtil.SUCCESS(service.delete(user.getUserId(), user.getMajorType(), sessionId, request));
    }

    @GetMapping("/study/plan-tasks")
    @Operation(summary = "본인 학습계획에서 기록에 연결할 과목 항목 조회", description =
            "date 생략 시 전체 일정, includeReplaced=true면 이전 계획도 포함합니다. 실제 taskId와 계획 버전을 제공합니다.")
    public ResponseEntity<ResponseDto<PlanTaskPageResponse>> planTasks(
            @AuthenticationPrincipal JwtPrincipal principal,
            @RequestParam(required = false) String date,
            @RequestParam(defaultValue = "false") boolean includeReplaced,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int pageSize) {
        JwtPrincipal user = requirePrincipal(principal);
        return ResponseUtil.SUCCESS(service.planTasks(user.getUserId(), user.getMajorType(), parseQueryDate(date),
                includeReplaced, page, pageSize));
    }

    @GetMapping("/study/sessions")
    @Operation(summary = "본인의 기간별 공부기록 조회", description =
            "양 끝 날짜 포함 최대 366일. page는 0부터, pageSize는 기본 20·최대 100입니다. " +
            "날짜·기록 ID 내림차순이며 교체된 계획 및 계획 미연결 기록도 포함합니다.")
    public ResponseEntity<ResponseDto<SessionPageResponse>> sessions(
            @AuthenticationPrincipal JwtPrincipal principal,
            @RequestParam String startDate,
            @RequestParam String endDate,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int pageSize) {
        JwtPrincipal user = requirePrincipal(principal);
        return ResponseUtil.SUCCESS(service.findSessions(user.getUserId(), user.getMajorType(),
                parseQueryDate(startDate), parseQueryDate(endDate), page, pageSize));
    }

    @GetMapping("/dashboard/study-stats")
    @Operation(summary = "본인의 실제 공부시간 통계", description =
            "period=LAST_7_DAYS(기본), LAST_30_DAYS 또는 CUSTOM. CUSTOM만 두 날짜를 받습니다. " +
            "서울 날짜별 실제 분을 오름차순으로 제공하며 빈 날짜는 0분, completionRate는 null입니다.")
    public ResponseEntity<ResponseDto<StudyStatsResponse>> stats(
            @AuthenticationPrincipal JwtPrincipal principal,
            @RequestParam(required = false) String period,
            @RequestParam(required = false) String startDate,
            @RequestParam(required = false) String endDate) {
        JwtPrincipal user = requirePrincipal(principal);
        return ResponseUtil.SUCCESS(service.getStats(user.getUserId(), user.getMajorType(),
                period, parseQueryDate(startDate), parseQueryDate(endDate)));
    }

    /** 값이 전달된 빈 문자열과 오프셋 날짜도 생략으로 취급하지 않는다. */
    private static LocalDate parseQueryDate(String value) {
        if (value == null) return null;
        if (value.length() != 10 || !value.matches("\\d{4}-\\d{2}-\\d{2}"))
            throw new StudyException(ErrorCode.INVALID_REQUEST, "날짜는 YYYY-MM-DD로 입력해 주세요.");
        try {
            return LocalDate.parse(value);
        } catch (DateTimeParseException e) {
            throw new StudyException(ErrorCode.INVALID_REQUEST, "존재하는 날짜를 입력해 주세요.");
        }
    }

    private static JwtPrincipal requirePrincipal(JwtPrincipal principal) {
        if (principal == null || principal.getUserId() == null || principal.getUserId() <= 0)
            throw new StudyException(ErrorCode.FAILURE_JWT_VERIFIED, "다시 로그인해 주세요.");
        return principal;
    }
}
