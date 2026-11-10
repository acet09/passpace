package com.passpace.user.service;

import com.passpace.user.dto.GoalForm;
import com.passpace.user.dto.UserViews.ExamRoundOption;
import com.passpace.user.dto.UserViews.SubjectOption;

import java.util.List;

/** [한결] 마이페이지 학습 목표 (목표 시험, 하루 가용시간, 과목별 이해도) */
public interface GoalService {

    /** 저장된 목표로 채운 입력 폼 (없으면 빈 폼) */
    GoalForm getGoalForm(Long userId);

    void saveGoal(Long userId, GoalForm form);

    List<ExamRoundOption> getExamRoundOptions();

    List<SubjectOption> getSubjects();
}
