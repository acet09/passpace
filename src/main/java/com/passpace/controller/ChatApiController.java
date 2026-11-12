package com.passpace.controller;

import com.passpace.dto.chat.ChatDtos.ChatRequest;
import com.passpace.service.ChatService;
import com.passpace.auth.LoginUser;
import com.passpace.constant.SessionConst;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * [동건] 챗봇 API. 화면(chatbot.js)이 fetch 로 호출한다.
 * 요청 {"message":"...", "conId": null} → 응답 ChatResponse(JSON)
 *
 * 챗봇은 로그인 사용자만 쓸 수 있다.
 *  - 비로그인 요청은 401 + {"error": "..."} (화면에서도 위젯이 잠겨 있어 보통은 오지 않는다)
 *  - 로그인 정보는 공통 계약(SessionConst.LOGIN_USER)으로만 읽는다 → 한결의 코드를 import 하지 않음
 *  - 한결의 LoginCheckInterceptor 에 /api/chat 을 넣지 않는다 (HTML 로그인 화면으로 redirect 되면 fetch 가 JSON 을 못 읽음)
 */
@RestController
public class ChatApiController {

    static final String LOGIN_REQUIRED = "로그인 후 이용할 수 있습니다.";

    private final ChatService chatService;

    public ChatApiController(ChatService chatService) {
        this.chatService = chatService;
    }

    @PostMapping("/api/chat")
    public ResponseEntity<?> chat(@RequestBody ChatRequest request, HttpServletRequest httpRequest) {
        HttpSession session = httpRequest.getSession(false);
        Object user = session == null ? null : session.getAttribute(SessionConst.LOGIN_USER);
        if (!(user instanceof LoginUser loginUser)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", LOGIN_REQUIRED));
        }
        return ResponseEntity.ok(chatService.answer(request, loginUser));
    }
}
