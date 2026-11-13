package com.passpace.dto.auth;

import jakarta.validation.constraints.NotBlank;

/** 로그인 요청 (POST /auth/login). passpace 는 이메일이 아니라 아이디(loginId)로 로그인한다 */
public record LoginUserRequestDto(
        @NotBlank(message = "아이디를 입력해 주세요.") String loginId,
        @NotBlank(message = "비밀번호를 입력해 주세요.") String password
) {}
