package com.passpace.controller;

import com.passpace.dto.auth.LoginUserRequestDto;
import com.passpace.dto.auth.SignupRequestDto;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.service.AuthService;
import com.passpace.util.ResponseUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirements;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 인증 API — 강의안 12주차 AuthController 와 같은 주소·모양.
 *
 *   POST /auth/signup     누구나          → data: { userId }
 *   POST /auth/login      누구나          → data: { accessToken, expiresInSeconds }
 *   GET  /auth/user-info  로그인(토큰)    → data: { userId, loginId, nickname, email, majorType, role, ... }
 *
 * 로그아웃 API 는 없다: 토큰 방식은 "화면(앱)이 저장한 토큰을 지우면 로그아웃" 이다 (static/js/auth.js 의 logout).
 * [passpace] 예전 세션 방식 AuthController(화면 + 세션 저장)를 이 JSON API 로 바꿨다.
 *            로그인·회원가입 "화면"은 PageController 가 돌려준다.
 */
@Tag(name = "인증 (Auth)", description = "회원가입 · 로그인(JWT 발급) · 내 정보")
@RestController
@RequiredArgsConstructor
@RequestMapping("/auth")
public class AuthController {

    private final AuthService authService;

    @Operation(summary = "회원가입", description = "일반 사용자(USER)로 가입합니다. **인증 불필요**")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "data: { userId }"),
            @ApiResponse(responseCode = "400", description = "INVALID_REQUEST (입력 규칙 위반, 비밀번호 확인 불일치)"),
            @ApiResponse(responseCode = "409", description = "DUPLICATED_LOGIN_ID · DUPLICATED_EMAIL")
    })
    @SecurityRequirements            // Swagger 에서 이 API 는 자물쇠(토큰) 없이 표시
    @PostMapping("/signup")
    public ResponseEntity<?> signup(@Valid @RequestBody SignupRequestDto request) {
        return ResponseUtil.SUCCESS(authService.signup(request));
    }

    @Operation(summary = "로그인", description = """
            아이디·비밀번호가 맞으면 JWT 를 발급합니다. **인증 불필요**

            받은 `accessToken` 을 이후 요청 헤더에 `Authorization: Bearer {accessToken}` 으로 넣습니다.
            """)
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "data: { accessToken, expiresInSeconds }"),
            @ApiResponse(responseCode = "400", description = "FAILURE_LOGIN (아이디 없음·비밀번호 틀림을 구분하지 않음)")
    })
    @SecurityRequirements
    @PostMapping("/login")
    public ResponseEntity<?> login(@Valid @RequestBody LoginUserRequestDto request) {
        return ResponseUtil.SUCCESS(authService.login(request));
    }

    @Operation(summary = "내 정보", description = "토큰의 userId 로 내 정보를 조회합니다. 화면 위쪽 '닉네임 님' 표시에도 씁니다.")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "data: { userId, loginId, nickname, email, majorType, role, createdAt }"),
            @ApiResponse(responseCode = "401", description = "토큰 없음·만료·변조")
    })
    @GetMapping("/user-info")
    public ResponseEntity<?> userInfo(@AuthenticationPrincipal JwtPrincipal loginUser) {
        // loginUser 는 JwtFilter 가 토큰을 풀어 넣어 둔 값 — 세션을 보지 않는다
        return ResponseUtil.SUCCESS(authService.findOneUser(loginUser));
    }
}
