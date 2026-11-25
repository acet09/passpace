package com.passpace.schedule;

import com.passpace.dto.ResponseDto;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.schedule.PlanScheduleDtos.Change;
import com.passpace.schedule.PlanScheduleDtos.Period;
import com.passpace.schedule.PlanScheduleDtos.PeriodUpdated;
import com.passpace.schedule.PlanScheduleDtos.Updated;
import com.passpace.util.ResponseUtil;
import io.swagger.v3.oas.annotations.Operation;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/** [한결] 계획의 기존 학습 항목 하나에 수동 일정을 반영한다. */
@RestController
public class PlanScheduleController {
    private final PlanScheduleService service;

    public PlanScheduleController(PlanScheduleService service) {
        this.service = service;
    }

    @PatchMapping("/api/chat/planner/review-based/plans/{planId}/tasks/{taskId}")
    @Operation(summary = "저장된 계획 항목의 날짜 또는 배정 시간 수정")
    public ResponseEntity<ResponseDto<Updated>> change(
            @AuthenticationPrincipal JwtPrincipal member, @PathVariable long planId,
            @PathVariable long taskId, @RequestBody Change request) {
        return ResponseUtil.SUCCESS(service.change(member, planId, taskId, request));
    }

    @PatchMapping("/api/chat/planner/review-based/plans/{planId}/period")
    @Operation(summary = "저장된 계획 전체의 시작일과 종료일 수정")
    public ResponseEntity<ResponseDto<PeriodUpdated>> changePeriod(
            @AuthenticationPrincipal JwtPrincipal member,
            @PathVariable long planId, @RequestBody Period request) {
        return ResponseUtil.SUCCESS(service.changePeriod(member, planId, request));
    }
}
