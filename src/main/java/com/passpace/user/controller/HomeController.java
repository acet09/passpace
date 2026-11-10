package com.passpace.user.controller;

import com.passpace.user.service.HomeService;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

/** [한결] ① 메인 페이지 */
@Controller
public class HomeController {

    private final HomeService homeService;

    public HomeController(HomeService homeService) {
        this.homeService = homeService;
    }

    @GetMapping("/")
    public String home(Model model) {
        // TODO(한결): 구현
        model.addAttribute("exams", homeService.getUpcomingExams());

        return "home";
    }
}
