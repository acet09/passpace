package com.passpace.collect.web;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * [용성] 관리자 비밀번호 확인 화면 /admin/login
 *  - 비밀번호는 application-local.yml 의 passpace.admin.password (git 에 올리지 않는 파일)
 *  - 값이 비어 있으면 관리자 화면 전체를 잠근다 (설정을 빠뜨려도 열린 채로 두지 않음)
 *  - 맞으면 세션에 표시 → 브라우저를 닫거나 세션이 끝날 때까지(60분 미사용) 다시 묻지 않음
 */
@Controller
public class AdminLoginController {

    private final String adminPassword;

    public AdminLoginController(@Value("${passpace.admin.password:}") String adminPassword) {
        this.adminPassword = adminPassword == null ? "" : adminPassword;
    }

    @GetMapping("/admin/login")
    public String form(@RequestParam(value = "redirectURL", required = false) String redirectURL, Model model) {
        model.addAttribute("redirectURL", safeRedirect(redirectURL));
        model.addAttribute("configured", !adminPassword.isBlank());
        return "collect/admin_login";
    }

    @PostMapping("/admin/login")
    public String login(@RequestParam(value = "password", required = false) String password,
                        @RequestParam(value = "redirectURL", required = false) String redirectURL,
                        HttpServletRequest request, Model model) {
        String target = safeRedirect(redirectURL);
        if (!adminPassword.isBlank() && password != null && matches(password)) {
            request.getSession(true);
            request.changeSessionId();                 // 로그인 전후 세션 아이디를 바꿔 고정 공격 방지
            request.getSession().setAttribute(AdminAuthInterceptor.ADMIN_SESSION_KEY, Boolean.TRUE);
            return "redirect:" + target;
        }
        try {
            Thread.sleep(1000);                        // 틀리면 1초 지연 (반복 대입 완화)
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        model.addAttribute("redirectURL", target);
        model.addAttribute("configured", !adminPassword.isBlank());
        model.addAttribute("error", adminPassword.isBlank()
                ? "관리자 비밀번호가 설정되지 않았습니다. application-local.yml 에 passpace.admin.password 를 적고 서버를 다시 시작하세요."
                : "비밀번호가 맞지 않습니다.");
        return "collect/admin_login";
    }

    @PostMapping("/admin/logout")
    public String logout(HttpServletRequest request) {
        HttpSession session = request.getSession(false);
        if (session != null) session.removeAttribute(AdminAuthInterceptor.ADMIN_SESSION_KEY);
        return "redirect:/admin/login";     // 사이트 홈이 아니라 관리자 로그인 화면으로
    }

    /** 걸리는 시간으로 비밀번호를 추측하지 못하게 바이트 비교 */
    private boolean matches(String input) {
        return MessageDigest.isEqual(input.getBytes(StandardCharsets.UTF_8), adminPassword.getBytes(StandardCharsets.UTF_8));
    }

    /** 로그인 후 이동은 관리자 화면 안쪽 주소로만 (외부 주소로 보내는 것 방지) */
    public static String safeRedirect(String url) {
        if (url == null || !url.startsWith("/admin") || url.startsWith("//") || url.contains("\\")
                || url.startsWith("/admin/login")) {
            return "/admin/collect";
        }
        return url;
    }
}
