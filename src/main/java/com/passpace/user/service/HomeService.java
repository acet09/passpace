package com.passpace.user.service;

import com.passpace.user.dto.UserViews.UpcomingExam;

import java.util.List;

/** [한결] 메인 페이지 데이터 */
public interface HomeService {

    /** 다가오는 정보처리기사 시험 일정 (없으면 빈 목록 → 화면에 "일정 준비 중") */
    List<UpcomingExam> getUpcomingExams();
}
