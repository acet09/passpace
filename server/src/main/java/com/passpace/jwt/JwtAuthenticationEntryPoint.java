package com.passpace.jwt;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import com.passpace.error.ErrorCode;
import com.passpace.error.ErrorResponseDto;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.stereotype.Component;

import java.io.IOException;

/** Security 규칙에서 "로그인 안 됨"으로 막힌 요청(401)도 우리 JSON 모양으로 응답한다 */
@Component
public class JwtAuthenticationEntryPoint implements AuthenticationEntryPoint {
    @Override
    public void commence(HttpServletRequest request, HttpServletResponse response, AuthenticationException authException)
            throws IOException {
        JwtExceptionHandlerFilter.writeError(response, 401, new ErrorResponseDto(ErrorCode.FAILURE_JWT_VERIFIED));
    }
}
