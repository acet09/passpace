package com.passpace.repository;

import com.passpace.dto.user.UserViews.UpcomingExam;

import java.util.List;

/** [한결] 메인 페이지 조회 (EXAM_ROUNDS 읽기 전용 - 테이블은 용성이 채운다) */
public interface HomeRepository {

    List<UpcomingExam> findUpcomingExams(String examCode, int limit);
}
