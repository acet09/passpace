package com.passpace.collect.web;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import org.springframework.web.servlet.HandlerInterceptor;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/**
 * [용성] 관리자 화면(/admin/**) 잠금.
 * 관리자 비밀번호(passpace.admin.password)를 맞게 입력한 세션만 통과시킨다.
 *  - 화면(GET) 요청 → /admin/login 으로 보냄
 *  - 버튼 요청(POST 등) → 401 JSON (화면의 스크립트가 "다시 로그인" 안내를 띄움)
 * 회원 로그인(한결 LoginCheckInterceptor)과는 별개다.
 */
public class AdminAuthInterceptor implements HandlerInterceptor {

    public static final String ADMIN_SESSION_KEY = "passpaceAdminAuth";

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        HttpSession session = request.getSession(false);
        if (session != null && Boolean.TRUE.equals(session.getAttribute(ADMIN_SESSION_KEY))) {
            return true;
        }
        if ("GET".equalsIgnoreCase(request.getMethod())) {
            String target = request.getRequestURI();
            if (request.getQueryString() != null) target += "?" + request.getQueryString();
            response.sendRedirect("/admin/login?redirectURL=" + URLEncoder.encode(target, StandardCharsets.UTF_8));
        } else {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.setContentType("application/json;charset=UTF-8");
            response.getWriter().write("{\"status\":\"UNAUTHORIZED\",\"message\":\"관리자 로그인이 필요합니다. 페이지를 새로고침하세요.\"}");
        }
        return false;
    }
}
