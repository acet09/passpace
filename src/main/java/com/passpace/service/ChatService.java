package com.passpace.service;

import com.passpace.dto.chat.ChatDtos.ChatRequest;
import com.passpace.dto.chat.ChatDtos.ChatResponse;
import com.passpace.auth.LoginUser;

/** [동건] 챗봇 */
public interface ChatService {

    /**
     * @param loginUser 로그인 사용자 (null 이면 안 됨 - 비로그인은 컨트롤러에서 401 로 막는다)
     */
    ChatResponse answer(ChatRequest request, LoginUser loginUser);
}
