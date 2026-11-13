package com.passpace.jwt;

import com.passpace.constant.MajorType;
import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * "지금 요청을 보낸 사람" 정보. JwtFilter 가 토큰을 풀어 만들고 SecurityContext 에 넣어 둔다.
 * Controller 에서는 @AuthenticationPrincipal JwtPrincipal loginUser 로 바로 꺼내 쓴다.
 * DB 를 다시 조회하지 않아도 되도록 자주 쓰는 값을 토큰에 담아 둔다.
 *
 * [passpace] 로그인은 이메일이 아니라 아이디(loginId)로 한다.
 * 챗봇·학습계획이 전공 구분(majorType)을 쓰므로 함께 담는다 (마이페이지에서 바꾸면 토큰을 다시 받아야 반영).
 */
@Getter
@AllArgsConstructor
public class JwtPrincipal {
    private Long userId;
    private String loginId;
    private String nickname;
    private MajorType majorType;   // 모르면 null
    private String role;           // "ADMIN" 또는 "USER"

    public boolean isAdmin() {
        return "ADMIN".equals(role);
    }
}
