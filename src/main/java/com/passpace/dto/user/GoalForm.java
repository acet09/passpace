package com.passpace.dto.user;

import org.springframework.format.annotation.DateTimeFormat;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Max;


import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * [한결] 마이페이지 - 학습 목표 입력값 (모두 선택 입력)
 *  - 목표 회차를 고르면 그 회차의 시험 시작일이 목표 시험일이 된다
 *  - 회차가 없으면 목표 시험일을 직접 입력
 *  - 과목별 사전 이해도: 1(낯섦) / 2(보통) / 3(익숙함)  ← 기획안 3.3
 */
// TODO(한결): 필드에 검증 어노테이션(jakarta.validation) 추가 - 하루 가용시간 10~720분 (나머지는 선택 입력)
public class GoalForm {

    /** EXAM_ROUNDS.exam_round_id (선택) */
    private Long examRoundId;

    /** 목표 시험일 직접 입력 (회차를 고르지 않았을 때) */
    @DateTimeFormat(iso = DateTimeFormat.ISO.DATE)
    private LocalDate targetExamDate;

    /** 하루 가용 학습시간(분) → USER_GOALS.daily_minutes (확장 컬럼) */
    @Min(value = 10, message = "하루 가용시간은 10분 이상이어야 합니다.")
    @Max(value = 720, message = "하루 가용시간은 720분 이하여야 합니다.")
    private Integer dailyMinutes;

    /** 과목 ID(CERTIFICATION_SUBJECTS) → 이해도 1~3 → GOAL_SUBJECTS.familiarity_level */
    private Map<Long, Integer> familiarity = new LinkedHashMap<>();

    public Long getExamRoundId() { return examRoundId; }
    public void setExamRoundId(Long examRoundId) { this.examRoundId = examRoundId; }
    public LocalDate getTargetExamDate() { return targetExamDate; }
    public void setTargetExamDate(LocalDate targetExamDate) { this.targetExamDate = targetExamDate; }
    public Integer getDailyMinutes() { return dailyMinutes; }
    public void setDailyMinutes(Integer dailyMinutes) { this.dailyMinutes = dailyMinutes; }
    public Map<Long, Integer> getFamiliarity() { return familiarity; }
    public void setFamiliarity(Map<Long, Integer> familiarity) { this.familiarity = familiarity; }
}
