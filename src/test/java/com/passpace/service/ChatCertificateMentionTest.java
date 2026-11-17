package com.passpace.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** [동건] 채팅 질문에서 ADsP·컴활 1급을 알아보는 규칙 (chatbot.js 의 CERT_WORDS 와 같은 규칙) */
class ChatCertificateMentionTest {

    @Test
    void adspIsRecognizedByAbbreviationOrKoreanName() {
        assertTrue(ChatServiceImpl.mentionsAdsp("adsp 계획 짜줘"));
        assertTrue(ChatServiceImpl.mentionsAdsp("데이터분석 준전문가 준비하려고"));
        assertFalse(ChatServiceImpl.mentionsAdsp("정처기 필기 계획"));
    }

    @Test
    void computerLiteracyMeansFirstGradeUnlessSecondGradeIsNamed() {
        assertTrue(ChatServiceImpl.mentionsComputer1("컴활 1급 실기 계획"));
        assertTrue(ChatServiceImpl.mentionsComputer1("컴퓨터활용능력 공부 계획"));
        assertFalse(ChatServiceImpl.mentionsComputer1("컴활 2급 계획 짜줘"));
        // 1급과 2급을 함께 말하면 1급은 지원 대상이다
        assertTrue(ChatServiceImpl.mentionsComputer1("컴활 2급 말고 컴활 1급 계획"));
        assertFalse(ChatServiceImpl.mentionsComputer1(null));
    }
}
