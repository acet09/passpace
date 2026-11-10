package com.passpace.chat.repository;

import com.passpace.common.code.ExamType;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

/**
 * [동건] 챗봇 저장소
 * 쓰기: CHAT_CONVERSATIONS, CHAT_MESSAGES
 * 읽기: CERTIFICATIONS, CERTIFICATION_SUBJECTS, EXAM_ROUNDS (용성이 채운 테이블)
 * 챗봇은 로그인 사용자만 쓰므로 모든 대화가 저장된다.
 */
public interface ChatRepository {

    Optional<Long> findCertificationId(String examCode);

    /** 합격 기준 문장 (CERTIFICATIONS.pass_criteria) → LLM 자료에 넣어 "60점" 같은 숫자를 근거 있게 만든다 */
    Optional<String> findPassCriteria(long certificationId);

    /** 오늘 이후 가장 가까운 시험 시작일 (질문에 시험일이 없을 때 제안용) */
    Optional<LocalDate> findNearestExamStart(long certificationId, ExamType examType, LocalDate today);

    List<String> findSubjectNames(long certificationId, ExamType examType);

    Long createConversation(Long userId, String title);

    boolean isOwner(Long conId, Long userId);

    void insertMessage(Long conId, String role, String content);

    /** 이 대화방에서 사용자가 앞서 보낸 질문 (최근 것부터 limit 개) → 이어지는 질문에서 빠진 조건을 채운다 */
    List<String> findRecentUserMessages(Long conId, int limit);
}
