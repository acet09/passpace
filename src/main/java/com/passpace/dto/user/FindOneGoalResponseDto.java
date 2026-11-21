package com.passpace.dto.user;

import com.passpace.dto.user.UserViews.ExamRoundOption;
import com.passpace.dto.user.UserViews.SubjectOption;

import java.util.List;

/**
 * 마이페이지 학습 목표 화면에 필요한 값 한 번에 (GET /users/me/goal).
 *  - goal       : 지금 저장된 목표 (없으면 빈 값)
 *  - examRounds : 목표 회차 선택 상자 목록
 *  - subjects   : 과목별 이해도 입력 줄 목록
 */
public record FindOneGoalResponseDto(UpdateGoalRequestDto goal,
                                     List<ExamRoundOption> examRounds,
                                     List<SubjectOption> subjects) {
}
