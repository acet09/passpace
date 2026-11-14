package com.passpace.service;

import com.passpace.dto.chat.ChatDtos.ChatRequest;
import com.passpace.dto.chat.ChatDtos.ChatResponse;
import com.passpace.jwt.JwtPrincipal;

/** [동건] 챗봇 */
public interface ChatService {

    /**
     * @param loginUser 로그인 사용자 (토큰에서 꺼낸 값. 토큰이 없으면 JwtFilter 가 401 로 먼저 막는다)
     */
    ChatResponse answer(ChatRequest request, JwtPrincipal loginUser);
}
