package com.passpace.user.controller;

import com.passpace.common.LoginUser;
import com.passpace.common.SessionConst;
import com.passpace.common.code.MajorType;
import com.passpace.user.dto.GoalForm;
import com.passpace.user.dto.ProfileForm;
import com.passpace.user.dto.UserViews.UserProfile;
import com.passpace.user.exception.DuplicateUserException;
import com.passpace.user.service.GoalService;
import com.passpace.user.service.UserService;
import jakarta.servlet.http.HttpSession;
import jakarta.validation.Valid;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.SessionAttribute;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

/**
 * [한결] ④ 마이페이지 - 회원정보 조회·수정, 학습 목표 입력.
 * 로그인하지 않은 사용자는 LoginCheckInterceptor 가 로그인 화면으로 보낸다.
 */
@Controller
public class MyPageController {

    private final UserService userService;
    private final GoalService goalService;

    public MyPageController(UserService userService, GoalService goalService) {
        this.userService = userService;
        this.goalService = goalService;
    }

    @ModelAttribute("majorTypes")
    public MajorType[] majorTypes() {
        // TODO(한결): 구현
        return MajorType.values();
    }

    @GetMapping("/mypage")
    public String myPage(@SessionAttribute(SessionConst.LOGIN_USER) LoginUser loginUser, Model model) {
        // TODO(한결): 구현
        UserProfile profile = userService.getProfile(loginUser.userId());

        fillPage(model, profile);

        return "user/mypage";
    }

    @PostMapping("/mypage/profile")
    public String updateProfile(@SessionAttribute(SessionConst.LOGIN_USER) LoginUser loginUser,
                                @Valid @ModelAttribute("profileForm") ProfileForm form, BindingResult binding,
                                HttpSession session, Model model, RedirectAttributes redirect) {
        // TODO(한결): 구현
        if (binding.hasErrors()) {
            fillPage(model, userService.getProfile(loginUser.userId()));
            return "user/mypage";
        }

        try {
            LoginUser updated = userService.updateProfile(
                    loginUser.userId(), form
            );

            session.setAttribute(SessionConst.LOGIN_USER, updated);

            redirect.addFlashAttribute("message", "회원정보를 수정했습니다.");

            return "redirect:/mypage";

        } catch (DuplicateUserException e) {
            binding.rejectValue(
                    e.getField(), "duplicate", e.getMessage()
            );

            fillPage(model, userService.getProfile(loginUser.userId()));
            return "user/mypage";
        }
    }

    @PostMapping("/mypage/goal")
    public String saveGoal(@SessionAttribute(SessionConst.LOGIN_USER) LoginUser loginUser,
                           @Valid @ModelAttribute("goalForm") GoalForm form, BindingResult binding,
                           Model model, RedirectAttributes redirect) {
        // TODO(한결): 구현
        if (binding.hasErrors()) {
            fillPage(model, userService.getProfile(loginUser.userId()));
            return "user/mypage";
        }

        try {
            goalService.saveGoal(loginUser.userId(), form);

        } catch (IllegalArgumentException e) {
            binding.reject("invalidGoal", e.getMessage());

            fillPage(model, userService.getProfile(loginUser.userId()));
            return "user/mypage";
        }

        redirect.addFlashAttribute("message", "학습 목표를 저장했습니다.");
        return "redirect:/mypage";
    }

    /** 화면에 공통으로 필요한 값 */
    private void fillPage(Model model, UserProfile profile) {
        // TODO(한결): 구현
        model.addAttribute("profile", profile);

        if (!model.containsAttribute("profileForm")) {
            ProfileForm profileForm = new ProfileForm();

            profileForm.setNickname(profile.nickname());
            profileForm.setEmail(profile.email());
            profileForm.setMajorType(profile.majorType());

            model.addAttribute("profileForm", profileForm);
        }

        if (!model.containsAttribute("goalForm")) {
            model.addAttribute(
                    "goalForm", goalService.getGoalForm(profile.userId())
            );
        }

        model.addAttribute("examRounds", goalService.getExamRoundOptions());
        model.addAttribute("subjects", goalService.getSubjects());
    }
}
