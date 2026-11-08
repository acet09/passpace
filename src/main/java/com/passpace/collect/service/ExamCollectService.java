package com.passpace.collect.service;

import com.passpace.collect.dto.CollectDtos.CollectResult;

/** [용성] 정보처리기사 시험일정 수집 (공공데이터 API → EXAM_ROUNDS) */
public interface ExamCollectService {

    CollectResult collectExamSchedule();
}
