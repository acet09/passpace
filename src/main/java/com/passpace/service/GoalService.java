package com.passpace.service;

import com.passpace.dto.user.UpdateGoalRequestDto;
import com.passpace.dto.user.UserViews.ExamRoundOption;
import com.passpace.dto.user.UserViews.SubjectOption;

import java.util.List;

/** [한결] 마이페이지 학습 목표 (목표 시험, 하루 가용시간, 과목별 이해도) */
public interface GoalService {

    /** 저장된 목표 (없으면 빈 값). 마이페이지 화면이 처음 열릴 때 입력칸을 채우는 데 쓴다 */
    UpdateGoalRequestDto getGoalForm(Long userId);

    void saveGoal(Long userId, UpdateGoalRequestDto form);

    List<ExamRoundOption> getExamRoundOptions();

    List<SubjectOption> getSubjects();
}
