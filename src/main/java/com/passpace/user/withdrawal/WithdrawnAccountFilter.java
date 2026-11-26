package com.passpace.user.withdrawal;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.passpace.constant.ResponseStatus;
import com.passpace.dto.ResponseDto;
import com.passpace.error.ErrorCode;
import com.passpace.error.ErrorResponseDto;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.jwt.SecurityPaths;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.core.annotation.Order;
import org.springframework.dao.DataAccessException;
import org.springframework.http.MediaType;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/** [한결] 기존 보안 필터(-100) 뒤에서 탈퇴 계정의 이전 JWT를 모든 보호 API에서 차단한다. */
@Component
@Order(-90)
public class WithdrawnAccountFilter extends OncePerRequestFilter {
    private final AccountWithdrawalRepository repository;
    private final ObjectMapper mapper;

    public WithdrawnAccountFilter(AccountWithdrawalRepository repository, ObjectMapper mapper) {
        this.repository = repository;
        this.mapper = mapper;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return SecurityPaths.isPublic(request.getRequestURI());
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        var authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !(authentication.getPrincipal() instanceof JwtPrincipal member)) {
            reject(response, ErrorCode.FAILURE_JWT_VERIFIED);
            return;
        }
        try {
            if (AccountWithdrawalRepository.isWithdrawn(member.getLoginId()) ||
                    !repository.isCurrentIdentity(member.getUserId(), member.getLoginId())) {
                reject(response, ErrorCode.FAILURE_JWT_VERIFIED);
                return;
            }
        } catch (DataAccessException e) {
            reject(response, ErrorCode.SERVICE_UNAVAILABLE);
            return;
        }
        chain.doFilter(request, response);
    }

    private void reject(HttpServletResponse response, ErrorCode code) throws IOException {
        SecurityContextHolder.clearContext();
        response.setStatus(code.getStatus());
        response.setCharacterEncoding("UTF-8");
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        mapper.writeValue(response.getWriter(),
                new ResponseDto<>(ResponseStatus.ERROR, code.getStatus(), new ErrorResponseDto(code)));
    }
}
