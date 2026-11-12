package com.passpace.controller;

import com.passpace.auth.LoginUser;
import com.passpace.constant.SessionConst;
import com.passpace.constant.MajorType;
import com.passpace.dto.user.LoginForm;
import com.passpace.dto.user.SignUpForm;
import com.passpace.error.exception.DuplicateUserException;
import com.passpace.error.exception.LoginFailedException;
import com.passpace.service.UserService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import jakarta.validation.Valid;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

import java.net.URI;

import java.nio.charset.StandardCharsets;

/** [한결] ② 로그인 ③ 회원가입, 로그아웃 */
@Controller
public class AuthController {

    private final UserService userService;

    public AuthController(UserService userService) {
        this.userService = userService;
    }

    /** 회원가입·마이페이지의 전공 선택 상자에 쓰는 값 */
    @ModelAttribute("majorTypes")
    public MajorType[] majorTypes() {
        // TODO(한결): 구현
        return MajorType.values();
    }

    // ---------------- 회원가입 ----------------

    @GetMapping("/signup")
    public String signupForm(Model model) {
        // TODO(한결): 구현
        model.addAttribute("form", new SignUpForm());

        return "user/signup";
    }

    @PostMapping("/signup")
    public String signup(@Valid @ModelAttribute("form") SignUpForm form, BindingResult binding,
                         HttpServletRequest request) {
        // TODO(한결): 구현
        if (form.getPassword() != null
                && form.getPassword().getBytes(StandardCharsets.UTF_8).length > 72) {
            binding.rejectValue(
                    "password",
                    "passwordTooLong",
                    "비밀번호는 72바이트 이하여야 합니다. 한글만 입력하면 최대 24자입니다."
            );
        }

        if (binding.hasErrors()) {
            return "user/signup";
        }

        if (form.getPassword() != null
                && !form.getPassword().equals(form.getPasswordConfirm())) {
            binding.rejectValue(
                    "passwordConfirm",
                    "passwordMismatch",
                    "비밀번호가 일치하지 않습니다."
            );
    }
        if (binding.hasErrors()) {
            return "user/signup";
        }

        try {
            LoginUser loginUser = userService.signUp(form);

            startSession(request, loginUser);

            return "redirect:/mypage";

        } catch (DuplicateUserException e) {
            binding.rejectValue(
                    e.getField(),
                    "duplicate",
                    e.getMessage()
            );

            return "user/signup";
        }
    }


    // ---------------- 로그인 ----------------

    @GetMapping("/login")
    public String loginForm(Model model, @RequestParam(defaultValue = "/") String redirectURL) {
        // TODO(한결): 구현
        model.addAttribute("form", new LoginForm());

        model.addAttribute("redirectURL", safeRedirectURL(redirectURL));

        return "user/login";
    }

    @PostMapping("/login")
    public String login(@Valid @ModelAttribute("form") LoginForm form, BindingResult binding,
                        @RequestParam(defaultValue = "/") String redirectURL,
                        HttpServletRequest request, Model model) {
        // TODO(한결): 구현
        String targetURL = safeRedirectURL(redirectURL);

        model.addAttribute("redirectURL", targetURL);

        if (binding.hasErrors()) {
            return "user/login";
    }
        try {
            LoginUser loginUser = userService.login(
                    form.getLoginId(),
                    form.getPassword()
            );

            startSession(request, loginUser);

            return "redirect:" + targetURL;

        } catch (LoginFailedException e) {
            binding.reject("loginFailed", e.getMessage());

            return "user/login";
        }
    }

    // ---------------- 로그아웃 ----------------

    @PostMapping("/logout")
    public String logout(HttpServletRequest request) {
        // TODO(한결): 구현
        HttpSession session = request.getSession(false);

        if (session != null) {
            session.invalidate();
        }

        return "redirect:/";
    }

    /** 세션 고정 공격을 막기 위해 기존 세션을 버리고 새 세션에 로그인 정보를 저장 */
    private void startSession(HttpServletRequest request, LoginUser loginUser) {
        // TODO(한결): 구현
        HttpSession oldSession = request.getSession(false);

        if (oldSession != null) {
            oldSession.invalidate();
        }

        HttpSession session = request.getSession(true);

        session.setAttribute(SessionConst.LOGIN_USER, loginUser);
    }

    private String safeRedirectURL(String redirectURL) {
        if (redirectURL == null
                || !redirectURL.startsWith("/")
                || redirectURL.startsWith("//")) {
            return "/";
        }

        try {
            URI uri = URI.create(redirectURL);
            String path = uri.getPath();

            if (uri.isAbsolute()
                    || uri.getRawAuthority() != null
                    || path == null
                    || path.startsWith("//")
                    || path.contains("\\")
                    || path.chars().anyMatch(c ->
                    Character.isISOControl(c)
                            || Character.isWhitespace(c))) {
                return "/";
            }

            return uri.toASCIIString();

        } catch (IllegalArgumentException e) {
            return "/";
        }
    }
}
