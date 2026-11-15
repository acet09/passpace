package com.passpace.study;

import com.passpace.study.StudyDtos.DayTotal;
import com.passpace.study.StudyDtos.PlanTask;
import com.passpace.study.StudyDtos.SessionRow;
import com.passpace.study.StudyDtos.UserState;
import com.passpace.study.StudyDtos.PlanTaskChoice;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

/** [한결] 기존 USERS·STUDY_SESSIONS·계획 관계를 사용한다. 스키마 변경이나 계획 수정은 없다. */
public interface StudyRepository {
    /** 쓰기는 사용자 행을 잠근다. 호출 서비스가 트랜잭션을 소유한다. */
    Optional<UserState> findUser(long userId, boolean lock);

    /** 항목·상위 계획의 소유권을 함께 제한하고 쓰기 트랜잭션에서 관련 행을 잠근다. */
    Optional<PlanTask> findOwnedTaskForUpdate(long userId, long taskId);

    long insert(long userId, Long taskId, LocalDate studyDate, int durationMinutes);

    Optional<SessionRow> findOwnedSessionForUpdate(long userId, long sessionId);

    /** 기존 날짜/분을 함께 확인하며 다른 열은 변경하지 않는다. */
    int updateOwnedSession(long userId, long sessionId, LocalDate date, int minutes,
                           LocalDate expectedDate, int expectedMinutes, Long taskId, Long expectedTaskId);

    int deleteOwnedSession(long userId, long sessionId, LocalDate expectedDate, int expectedMinutes,
                           Long expectedTaskId);

    List<PlanTaskChoice> findOwnedPlanTasks(long userId, LocalDate date, boolean includeReplaced,
                                          int limit, long offset);

    List<SessionRow> findSessions(long userId, LocalDate startDate, LocalDate endDate,
                                  int limit, long offset);

    /** 개인 시간은 교체된 계획·계획 미연결 기록도 포함한다. */
    List<DayTotal> findDailyTotals(long userId, LocalDate startDate, LocalDate endDate);
}
