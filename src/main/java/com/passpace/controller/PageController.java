package com.passpace.controller;

import com.passpace.constant.MajorType;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

/**
 * [JWT] 화면(HTML 껍데기)만 돌려주는 컨트롤러.
 *
 * 세션이 없으므로 서버는 "누가 보고 있는지" 모른 채 모두에게 똑같은 HTML 을 준다.
 * 로그인 여부·회원 정보는 화면이 열린 뒤 JS(static/js/auth.js)가 토큰으로 API 를 불러 채운다.
 *   - 로그인 화면  → POST /auth/login 으로 토큰을 받아 저장
 *   - 마이페이지   → GET /auth/user-info, GET /users/me/goal 로 내용 채우기
 *   - 관리자 화면  → 토큰의 role 이 ADMIN 이 아니면 API 가 403 → 화면이 안내 표시
 * 그래서 이 주소들은 SecurityPaths.PUBLIC 에 열려 있다 (데이터는 API 쪽에서 토큰으로 지킨다).
 *
 * 나중에 앱(Flutter)을 만들면 이 클래스와 templates/ 는 쓰지 않고, 같은 API 를 앱이 부른다.
 * (메인 화면 "/" 은 로그인과 상관없는 시험 일정만 보여 주므로 HomeController 가 그대로 그린다)
 */
@Controller
public class PageController {

    @GetMapping("/login")
    public String login() {
        return "user/login";
    }

    @GetMapping("/signup")
    public String signup(Model model) {
        model.addAttribute("majorTypes", MajorType.values());   // 전공 선택 상자 (고정 목록이라 서버가 채워 줌)
        return "user/signup";
    }

    @GetMapping("/mypage")
    public String myPage(Model model) {
        model.addAttribute("majorTypes", MajorType.values());
        return "user/mypage";
    }

    @GetMapping("/admin/collect")
    public String adminCollect() {
        return "collect/admin";
    }
}
