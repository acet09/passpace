package com.passpace.jwt;

import com.passpace.constant.MajorType;
import com.passpace.error.ErrorCode;
import com.passpace.error.exception.JwtException;
import io.jsonwebtoken.Claims;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.Authentication;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * [JWT] 토큰 만들기·검증하기 테스트 (DB·서버 없이 실행).
 * 강의안 p.30~31 의 "토큰 내용을 고치면 서명이 맞지 않아 거절된다"를 코드로 확인한다.
 */
class JwtUtilTest {

    private JwtUtil jwtUtil;

    @BeforeEach
    void setUp() {
        // 스프링 없이 만들기 때문에 @Value 로 들어갈 값을 직접 넣는다
        jwtUtil = new JwtUtil();
        ReflectionTestUtils.setField(jwtUtil, "issuer", "passpace-test");
        ReflectionTestUtils.setField(jwtUtil, "secret",
                Base64.getEncoder().encodeToString("test-only-secret-key-at-least-32-bytes!!".getBytes(StandardCharsets.UTF_8)));
        ReflectionTestUtils.setField(jwtUtil, "accessTokenValidityInSeconds", 60L);
        jwtUtil.afterPropertiesSet();
    }

    @Test
    void 만든_토큰을_풀면_같은_사용자_정보가_나온다() {
        String token = jwtUtil.createToken(new JwtPrincipal(7L, "kim_01", "김패스", MajorType.MAJOR, "USER"));

        Claims claims = jwtUtil.validateToken(token);
        Authentication auth = jwtUtil.getAuthentication(claims, token);
        JwtPrincipal p = (JwtPrincipal) auth.getPrincipal();

        assertThat(p.getUserId()).isEqualTo(7L);
        assertThat(p.getLoginId()).isEqualTo("kim_01");
        assertThat(p.getNickname()).isEqualTo("김패스");
        assertThat(p.getMajorType()).isEqualTo(MajorType.MAJOR);
        assertThat(auth.getAuthorities()).extracting(Object::toString).containsExactly("ROLE_USER");
    }

    @Test
    void 전공을_모르는_회원도_토큰을_만들_수_있다() {
        String token = jwtUtil.createToken(new JwtPrincipal(8L, "lee", "이패스", null, "USER"));
        JwtPrincipal p = (JwtPrincipal) jwtUtil.getAuthentication(jwtUtil.validateToken(token), token).getPrincipal();
        assertThat(p.getMajorType()).isNull();
    }

    @Test
    void 내용을_고친_토큰은_INVALID_JWT() {
        String token = jwtUtil.createToken(new JwtPrincipal(7L, "kim_01", "김패스", MajorType.MAJOR, "USER"));

        // 가운데 부분(내용)을 role=ADMIN 으로 바꿔 끼운다 — 서명은 그대로
        String[] parts = token.split("\\.");
        String payload = new String(Base64.getUrlDecoder().decode(parts[1]), StandardCharsets.UTF_8)
                .replace("\"USER\"", "\"ADMIN\"");
        String forged = parts[0] + "." + Base64.getUrlEncoder().withoutPadding()
                .encodeToString(payload.getBytes(StandardCharsets.UTF_8)) + "." + parts[2];

        assertThatThrownBy(() -> jwtUtil.validateToken(forged))
                .isInstanceOf(JwtException.class)
                .extracting(e -> ((JwtException) e).getErrorCode())
                .isEqualTo(ErrorCode.INVALID_JWT);
    }

    @Test
    void 공개_주소와_API_주소가_겹치지_않는다() {
        assertThat(SecurityPaths.isPublic("/auth/login")).isTrue();
        assertThat(SecurityPaths.isPublic("/admin/collect")).isTrue();          // 화면 껍데기
        assertThat(SecurityPaths.isPublic("/admin/collect/exam")).isFalse();    // 데이터 API → ADMIN 토큰 필요
        assertThat(SecurityPaths.isPublic("/api/chat")).isFalse();
        assertThat(SecurityPaths.isPublic("/users/me")).isFalse();
        assertThat(SecurityPaths.isPublic("/auth/user-info")).isFalse();
    }
}
