package com.passpace.jwt;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import com.passpace.error.ErrorCode;
import com.passpace.error.ErrorResponseDto;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;

import java.io.IOException;

/** 로그인은 했지만 권한(hasRole)이 모자라 막힌 요청(403)을 우리 JSON 모양으로 응답한다 */
@Component
public class JwtAccessDeniedHandler implements AccessDeniedHandler {
    @Override
    public void handle(HttpServletRequest request, HttpServletResponse response, AccessDeniedException accessDeniedException)
            throws IOException {
        JwtExceptionHandlerFilter.writeError(response, 403, new ErrorResponseDto(ErrorCode.PERMISSION_DENIED));
    }
}
