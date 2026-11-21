package com.passpace.jwt;

import io.jsonwebtoken.Claims;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;
import jakarta.servlet.http.HttpServletRequest;
import com.passpace.error.ErrorCode;
import com.passpace.error.exception.JwtException;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.GenericFilterBean;

import java.io.IOException;

/**
 * 모든 요청이 Controller 에 닿기 전에 거치는 검문소.
 *  1) Authorization: Bearer xxxxx 헤더에서 토큰을 꺼내고
 *  2) 검증해서
 *  3) "이 요청은 누구의 것" 이라고 SecurityContext 에 적어 둔다.
 * @Component 를 붙이지 않는다 — 붙이면 일반 서블릿 필터로도 한 번 더 등록되어 요청마다 두 번 돈다.
 */
@RequiredArgsConstructor
public class JwtFilter extends GenericFilterBean {

    public static final String AUTHORIZATION_HEADER = "Authorization";
    private final JwtUtil jwtUtil;

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {
        HttpServletRequest httpRequest = (HttpServletRequest) request;
        String requestURI = httpRequest.getRequestURI();

        if (!SecurityPaths.isPublic(requestURI)) {   // 로그인·회원가입·Swagger 는 검사 생략
            String jwt = resolveToken(httpRequest);
            if (!StringUtils.hasText(jwt)) {
                throw new JwtException(ErrorCode.FAILURE_JWT_VERIFIED); // 토큰 없음 → 401
            }
            Claims claims = jwtUtil.validateToken(jwt);           // 서명·만료 확인
            Authentication authentication = jwtUtil.getAuthentication(claims, jwt);
            SecurityContextHolder.getContext().setAuthentication(authentication);
        }

        chain.doFilter(request, response);
    }

    /** "Bearer " 다음 글자만 꺼낸다 */
    private String resolveToken(HttpServletRequest request) {
        String bearerToken = request.getHeader(AUTHORIZATION_HEADER);
        if (StringUtils.hasText(bearerToken) && bearerToken.startsWith("Bearer ")) {
            return bearerToken.substring(7);
        }
        return null;
    }
}
