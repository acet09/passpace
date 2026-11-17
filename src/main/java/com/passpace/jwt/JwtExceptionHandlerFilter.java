package com.passpace.jwt;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import com.passpace.constant.ResponseStatus;
import com.passpace.dto.ResponseDto;
import com.passpace.error.ErrorResponseDto;
import com.passpace.error.exception.JwtException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * JwtFilter 바로 앞에서 JwtFilter 가 던진 JwtException 을 잡아 JSON 으로 응답한다.
 * 필터는 Controller 바깥이라 GlobalExceptionHandler(@RestControllerAdvice)가 잡지 못하기 때문에 필요하다.
 */
@Slf4j
public class JwtExceptionHandlerFilter extends OncePerRequestFilter {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        try {
            filterChain.doFilter(request, response);
        } catch (JwtException e) {
            log.warn("[JwtException] {} {} → {}", request.getMethod(), request.getRequestURI(), e.getErrorCode());
            writeError(response, e.getErrorCode().getStatus(), new ErrorResponseDto(e.getErrorCode()));
        }
    }

    /** EntryPoint·AccessDeniedHandler 도 같은 모양으로 쓰도록 static 으로 열어 둔다 */
    static void writeError(HttpServletResponse response, int status, ErrorResponseDto body) throws IOException {
        response.setStatus(status);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write(OBJECT_MAPPER.writeValueAsString(new ResponseDto<>(ResponseStatus.ERROR, status, body)));
    }
}
