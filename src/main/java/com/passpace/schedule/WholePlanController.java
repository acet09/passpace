package com.passpace.schedule;

import com.passpace.dto.ResponseDto;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.schedule.WholePlanDtos.Applied;
import com.passpace.schedule.WholePlanDtos.Edit;
import com.passpace.schedule.WholePlanDtos.Editor;
import com.passpace.schedule.WholePlanDtos.Preview;
import com.passpace.util.ResponseUtil;
import io.swagger.v3.oas.annotations.Operation;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** [한결] 사용 중인 계획의 전체 일정 수정. */
@RestController
@RequestMapping("/api/chat/planner/review-based/plans/{planId}/schedule")
public class WholePlanController {
    private final WholePlanService service;

    public WholePlanController(WholePlanService service) {
        this.service = service;
    }

    @GetMapping
    @Operation(summary = "현재 계획의 전체 수정 입력 조회")
    public ResponseEntity<ResponseDto<Editor>> editor(
            @AuthenticationPrincipal JwtPrincipal member, @PathVariable long planId) {
        return ResponseUtil.SUCCESS(service.editor(member, planId));
    }

    @PostMapping("/preview")
    @Operation(summary = "현재 계획의 전체 수정 미리보기")
    public ResponseEntity<ResponseDto<Preview>> preview(
            @AuthenticationPrincipal JwtPrincipal member, @PathVariable long planId, @RequestBody Edit edit) {
        return ResponseUtil.SUCCESS(service.preview(member, planId, edit));
    }

    @PatchMapping
    @Operation(summary = "확인한 변경을 같은 계획에 저장")
    public ResponseEntity<ResponseDto<Applied>> apply(
            @AuthenticationPrincipal JwtPrincipal member, @PathVariable long planId, @RequestBody Edit edit) {
        return ResponseUtil.SUCCESS(service.apply(member, planId, edit));
    }
}
