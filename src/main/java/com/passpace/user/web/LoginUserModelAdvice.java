package com.passpace.user.web;

import com.passpace.common.LoginUser;
import com.passpace.common.SessionConst;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ModelAttribute;

/**
 * [한결] 모든 화면에 로그인 사용자(loginUser)를 넣어 준다.
 * 공통 헤더(fragments/layout.html)가 이 값으로 "로그인 / 닉네임 님" 을 바꿔 보여 준다.
 * 용성의 관리자 화면처럼 다른 영역의 화면도 같은 헤더를 쓰므로 모든 @Controller 에 적용한다.
 */
@ControllerAdvice(annotations = Controller.class)
public class LoginUserModelAdvice {

    @ModelAttribute("loginUser")
    public LoginUser loginUser(HttpServletRequest request) {
        // TODO(한결): 구현
        HttpSession session = request.getSession(false);

        if (session == null) {
            return null;
        }

        return (LoginUser) session.getAttribute(SessionConst.LOGIN_USER);
    }
}
