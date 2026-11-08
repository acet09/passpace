package com.passpace.common.profile;

import com.passpace.common.code.MajorType;

import java.time.LocalDate;
import java.util.Map;

/**
 * [공통 계약] 로그인 사용자의 학습 조건 (마이페이지에서 입력한 값).
 * 한결이 USERS·USER_GOALS·GOAL_SUBJECTS 에서 읽어 만들고, 동건(챗봇)이 질문에 빠진 값을 채울 때 쓴다.
 *
 * @param userId               회원 ID
 * @param majorType            전공 구분
 * @param targetExamDate       목표 시험일 (없으면 null)
 * @param dailyMinutes         하루 가용 학습시간(분) (없으면 null)
 * @param familiarityBySubject 과목명 → 사전 이해도 1(낯섦)~3(익숙함)
 */
public record UserStudyProfile(Long userId, MajorType majorType, LocalDate targetExamDate,
                               Integer dailyMinutes, Map<String, Integer> familiarityBySubject) {
}
