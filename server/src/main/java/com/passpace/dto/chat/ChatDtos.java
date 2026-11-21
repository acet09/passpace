package com.passpace.dto.chat;

import com.passpace.constant.ExamType;
import com.passpace.constant.MajorType;

import java.time.LocalDate;
import java.util.List;

/** [동건] 챗봇에서 주고받는 값들 (record 모음) */
public final class ChatDtos {

    private ChatDtos() {
    }

    // ------------------------------------------------------------------
    // 화면 ↔ 서버
    // ------------------------------------------------------------------

    /** POST /api/chat 요청 본문. conId 는 같은 대화방에서 이어 물을 때 (처음엔 null) */
    public record ChatRequest(String message, Long conId) {
    }

    /**
     * POST /api/chat 응답 본문
     *
     * @param answer         사용자에게 보여 줄 답변
     * @param conId          대화방 ID (다음 질문 때 그대로 보내면 앞 질문의 조건을 이어 쓴다)
     * @param sampleSize     통계에 쓴 합격 후기 수
     * @param statsAvailable 표본이 기준(10건) 이상이라 통계를 썼는지
     * @param statsCondition 통계를 낸 조건 설명 (조건을 넓혔으면 그 단계)
     * @param sources        근거로 쓴 후기 출처 URL (최대 3개)
     * @param notice         안내 문구 (LLM 연결 실패, 표본 부족 등)
     * @param llmUsed        LLM 이 쓴 답변인지 (false 면 Java 기본 안내)
     */
    public record ChatResponse(String answer, Long conId, int sampleSize, boolean statsAvailable,
                               String statsCondition, List<String> sources, String notice, boolean llmUsed) {
    }

    // ------------------------------------------------------------------
    // 처리 단계별 값
    // ------------------------------------------------------------------

    /**
     * ① 질문에서 뽑은 조건 (없으면 null)
     *
     * @param examDatePast 연도까지 적은 시험일이 이미 지났는지 → 사용자에게 다시 물어본다
     */
    public record ExtractedCondition(MajorType majorType, ExamType examType, LocalDate examDate,
                                     boolean examDatePast, Integer dailyMinutes) {

        public ExtractedCondition withMissingFilled(ExtractedCondition other) {
            return new ExtractedCondition(
                    majorType != null ? majorType : other.majorType(),
                    examType != null ? examType : other.examType(),
                    examDate != null ? examDate : other.examDate(),
                    examDatePast,
                    dailyMinutes != null ? dailyMinutes : other.dailyMinutes());
        }
    }

    /** ② Java 가 계산한 계획 숫자 */
    public record PlanNumbers(int remainingDays, int weeks, int dailyMinutes, double totalHours,
                              List<PhasePlan> phases, List<SubjectPlan> subjects) {
    }

    /** 단계 (기초·이론 → 기출 반복 → 마무리) */
    public record PhasePlan(int order, String name, String rangeLabel, int percent, int days, double hours, String focus) {
    }

    /** 과목별 배분 (기획안 3.3: 이해도 1단계 1.3 / 2단계 1.0 / 3단계 0.7) */
    public record SubjectPlan(String subjectName, Integer familiarity, double weight, double hours) {
    }

    /** ③ 유사 집단 통계 */
    public record StatsSummary(boolean available, String conditionLabel, int sampleSize, int totalCount,
                               int passCount, int failCount,
                               Integer avgDailyMinutes, Integer medianDailyMinutes,
                               Integer minDailyMinutes, Integer maxDailyMinutes,
                               Integer avgTotalHours, Integer avgPrepDays,
                               String topMethodCode, int topMethodCount,
                               Integer failAvgDailyMinutes, List<Evidence> evidences) {
    }

    /** 근거 후기 1건 ([근거 n] 으로 LLM 에 전달) */
    public record Evidence(int no, String text, String url, Integer prepDays, Integer dailyMinutes) {
    }

    /** ④ 답변 생성 결과 */
    public record ComposedAnswer(String text, boolean llmUsed, List<String> sources, String notice) {
    }
}
