package com.passpace.study;

import com.passpace.constant.MajorType;
import com.passpace.study.StudyDtos.SaveSessionRequest;
import com.passpace.study.StudyDtos.SessionPageResponse;
import com.passpace.study.StudyDtos.SessionResponse;
import com.passpace.study.StudyDtos.StudyStatsResponse;
import com.passpace.study.StudyDtos.UpdateSessionRequest;
import com.passpace.study.StudyDtos.DeleteSessionRequest;
import com.passpace.study.StudyDtos.DeleteSessionResponse;
import com.passpace.study.StudyDtos.PlanTaskPageResponse;

import java.time.LocalDate;

/** [한결] 본인의 수동 공부기록과 실제 공부시간 통계. 계획 계산·승인·변경은 수행하지 않는다. */
public interface StudyService {
    SessionResponse save(long userId, MajorType authenticatedMajor, SaveSessionRequest request);
    SessionResponse update(long userId, MajorType authenticatedMajor, long sessionId, UpdateSessionRequest request);
    DeleteSessionResponse delete(long userId, MajorType authenticatedMajor, long sessionId, DeleteSessionRequest request);
    PlanTaskPageResponse planTasks(long userId, MajorType authenticatedMajor, LocalDate date,
                                   boolean includeReplaced, int page, int pageSize);
    SessionPageResponse findSessions(long userId, MajorType authenticatedMajor,
                                     LocalDate startDate, LocalDate endDate, int page, int pageSize);
    StudyStatsResponse getStats(long userId, MajorType authenticatedMajor,
                               String period, LocalDate startDate, LocalDate endDate);
}
