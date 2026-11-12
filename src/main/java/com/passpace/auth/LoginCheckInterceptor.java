package com.passpace.auth;

import com.passpace.constant.SessionConst;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import org.springframework.web.servlet.HandlerInterceptor;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/** [한결] 로그인이 필요한 주소(/mypage/**)에 비로그인 사용자가 오면 로그인 화면으로 보낸다. */
public class LoginCheckInterceptor implements HandlerInterceptor {

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        // TODO(한결): 구현
        HttpSession session = request.getSession(false);

        if (session != null
                && session.getAttribute(SessionConst.LOGIN_USER) != null) {
            return true;
        }

        String redirectURL = "/mypage";

        if ("GET".equalsIgnoreCase(request.getMethod())) {
            redirectURL = request.getRequestURI();

            String queryString = request.getQueryString();

            if (queryString != null && !queryString.isBlank()) {
                redirectURL += "?" + queryString;
            }
        }

        String encodedURL = URLEncoder.encode(
                redirectURL,
                StandardCharsets.UTF_8
        );

        response.sendRedirect("/login?redirectURL=" + encodedURL);

        return false;
    }
}
