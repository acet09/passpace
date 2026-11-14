package com.passpace.jwt;

import org.springframework.util.AntPathMatcher;

import java.util.Arrays;

/**
 * 토큰 없이 들어올 수 있는 주소 목록.
 * SecurityConfig(permitAll) 와 JwtFilter(토큰 검사 생략)가 같은 목록을 쓴다.
 * 두 곳에 따로 적으면 한쪽만 고쳐서 "열어 뒀는데 토큰을 요구"하는 일이 생기므로 여기서만 관리한다.
 *
 * 주의: 여기 적힌 주소는 GET·POST 구분 없이 열린다. 그래서 "화면 주소"와 "데이터 API 주소"를 겹치지 않게 만든다.
 *       예) GET /admin/collect (화면, 열림)  ↔  /admin/collect/** (데이터 API, ADMIN 만)
 */
public final class SecurityPaths {

    public static final String[] PUBLIC = {
            // ── 인증 API (강의안과 같음) ──
            "/auth/login",
            "/auth/signup",

            // ── Swagger (강의안과 같음) ──
            "/swagger-ui/**",
            "/swagger-ui.html",
            "/v3/api-docs",
            "/v3/api-docs/**",

            // ── [passpace] 웹 화면 (HTML 껍데기) ──
            //    화면 자체에는 개인 정보가 없다. 열린 뒤 JS 가 토큰으로 API 를 불러 내용을 채운다 (PageController 참고)
            "/",                 // 메인 (시험 일정은 누구나 볼 수 있음)
            "/login",
            "/signup",
            "/mypage",
            "/admin/collect",    // 관리자 화면 껍데기 — 버튼이 부르는 /admin/collect/** API 는 ADMIN 만
            "/css/**",
            "/js/**",
            "/favicon.ico",

            // ── 오류 화면 (Spring 이 오류를 보여 줄 때 내부적으로 /error 로 다시 보낸다) ──
            "/error",
    };

    private static final AntPathMatcher MATCHER = new AntPathMatcher();

    private SecurityPaths() {
    }

    public static boolean isPublic(String requestURI) {
        return Arrays.stream(PUBLIC).anyMatch(pattern -> MATCHER.match(pattern, requestURI));
    }
}
