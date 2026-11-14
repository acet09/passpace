package com.passpace.controller;

import com.passpace.dto.user.FindOneGoalResponseDto;
import com.passpace.dto.user.UpdateGoalRequestDto;
import com.passpace.dto.user.UpdateUserRequestDto;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.service.AuthService;
import com.passpace.service.GoalService;
import com.passpace.service.UserService;
import com.passpace.util.ResponseUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * [한결] 마이페이지 API (예전 MyPageController 를 JSON API 로 바꾼 것).
 * 주소의 "me" = 토큰 주인. 남의 userId 를 주소에 넣을 수 없게 해서 "본인만" 검사가 따로 필요 없다.
 *
 *   PUT  /users/me        회원정보 수정 → data: 새 토큰 (닉네임·전공이 토큰 안에 있어서 다시 발급)
 *   GET  /users/me/goal   학습 목표 + 회차 목록 + 과목 목록
 *   PUT  /users/me/goal   학습 목표 저장
 * (내 정보 조회는 GET /auth/user-info)
 */
@Tag(name = "회원 (User)", description = "마이페이지 — 회원정보 수정 · 학습 목표")
@RestController
@RequiredArgsConstructor
@RequestMapping("/users/me")
public class UserController {

    private final UserService userService;
    private final GoalService goalService;
    private final AuthService authService;

    @Operation(summary = "회원정보 수정", description = "닉네임·이메일·전공 구분을 바꾸고, 바뀐 값이 담긴 **새 토큰**을 돌려줍니다.")
    @PutMapping
    public ResponseEntity<?> updateUser(@AuthenticationPrincipal JwtPrincipal loginUser,
                                        @Valid @RequestBody UpdateUserRequestDto request) {
        userService.updateProfile(loginUser.getUserId(), request);
        // 토큰 안의 닉네임·전공은 옛 값 → 새 토큰을 돌려주고, 화면은 이걸로 바꿔 저장한다
        return ResponseUtil.SUCCESS(authService.reissueToken(loginUser.getUserId()));
    }

    @Operation(summary = "학습 목표 조회", description = "저장된 목표와, 화면 선택 상자에 쓸 회차·과목 목록")
    @GetMapping("/goal")
    public ResponseEntity<?> findGoal(@AuthenticationPrincipal JwtPrincipal loginUser) {
        return ResponseUtil.SUCCESS(new FindOneGoalResponseDto(
                goalService.getGoalForm(loginUser.getUserId()),
                goalService.getExamRoundOptions(),
                goalService.getSubjects()));
    }

    @Operation(summary = "학습 목표 저장", description = "모든 항목 선택 입력. 하루 가용시간은 10~720분")
    @PutMapping("/goal")
    public ResponseEntity<?> updateGoal(@AuthenticationPrincipal JwtPrincipal loginUser,
                                        @Valid @RequestBody UpdateGoalRequestDto request) {
        // 잘못된 값이면 GoalService 가 IllegalArgumentException → GlobalExceptionHandler 가 400 으로
        goalService.saveGoal(loginUser.getUserId(), request);
        return ResponseUtil.SUCCESS();
    }
}
