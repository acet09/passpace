package com.passpace.dto.auth;

/**
 * 로그인 성공: 이후 모든 요청의 Authorization: Bearer {accessToken} 에 넣을 토큰.
 * 웹 화면은 auth.js 가 이 값을 localStorage 에 저장한다 (앱은 secure storage 에 저장).
 * 회원정보를 수정했을 때도 같은 모양으로 새 토큰을 돌려준다 (토큰 안의 닉네임·전공이 바뀌므로).
 */
public record LoginUserResponseDto(String accessToken, long expiresInSeconds) {
}
