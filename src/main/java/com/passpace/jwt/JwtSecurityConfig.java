package com.passpace.jwt;

import lombok.RequiredArgsConstructor;
import org.springframework.security.config.annotation.SecurityConfigurerAdapter;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.DefaultSecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

/**
 * 우리 필터 두 개를 Spring Security 필터 줄에 끼워 넣는다.
 * 순서: JwtExceptionHandlerFilter → JwtFilter → (Security 기본 필터들) → Controller
 */
@RequiredArgsConstructor
public class JwtSecurityConfig extends SecurityConfigurerAdapter<DefaultSecurityFilterChain, HttpSecurity> {

    private final JwtUtil jwtUtil;

    @Override
    public void configure(HttpSecurity http) {
        http.addFilterBefore(new JwtExceptionHandlerFilter(), UsernamePasswordAuthenticationFilter.class);
        http.addFilterBefore(new JwtFilter(jwtUtil), UsernamePasswordAuthenticationFilter.class);
    }
}
