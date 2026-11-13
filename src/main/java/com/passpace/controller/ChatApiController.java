package com.passpace.controller;

import com.passpace.dto.chat.ChatDtos.ChatRequest;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.service.ChatService;
import com.passpace.util.ResponseUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * [동건] 챗봇 API. 화면(chatbot.js)이 fetch 로 호출한다.
 * 요청 {"message":"...", "conId": null} → 응답 {"status":"SUCCESS","code":200,"data": ChatResponse}
 *
 * [JWT] 챗봇은 로그인 사용자만 쓸 수 있다.
 *  - 예전: 세션에서 LoginUser 를 꺼내 없으면 401 을 직접 응답
 *  - 지금: 토큰이 없으면 JwtFilter 가 Controller 에 오기 전에 401 로 막는다
 *          → 여기서는 @AuthenticationPrincipal 로 "토큰 주인"을 받기만 하면 된다
 */
@Tag(name = "챗봇 (Chat)", description = "학습 상담 챗봇")
@RestController
public class ChatApiController {

    private final ChatService chatService;

    public ChatApiController(ChatService chatService) {
        this.chatService = chatService;
    }

    @Operation(summary = "챗봇 질문", description = "conId 가 없으면 새 대화방을 만들고, 응답의 conId 를 다음 질문에 넣습니다.")
    @PostMapping("/api/chat")
    public ResponseEntity<?> chat(@RequestBody ChatRequest request,
                                  @AuthenticationPrincipal JwtPrincipal loginUser) {
        return ResponseUtil.SUCCESS(chatService.answer(request, loginUser));
    }
}
