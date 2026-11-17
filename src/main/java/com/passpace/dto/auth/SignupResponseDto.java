package com.passpace.dto.auth;

/** 회원가입 성공: 새로 만들어진 회원 번호 (로그인은 따로 POST /auth/login 으로) */
public record SignupResponseDto(Long userId) {
}
