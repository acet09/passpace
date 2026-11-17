package com.passpace.repository;

import com.passpace.dto.user.UserViews.ActiveGoal;
import com.passpace.dto.user.UserViews.ExamRoundOption;
import com.passpace.dto.user.UserViews.SubjectOption;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * [한결] 학습 목표 저장소.
 * 쓰기: USER_GOALS, GOAL_SUBJECTS / 읽기: CERTIFICATIONS, EXAM_ROUNDS, CERTIFICATION_SUBJECTS (용성이 채운 테이블)
 */
public interface GoalRepository {

    /** 종목코드(1320) → certification_id */
    Optional<Long> findCertificationId(String examCode);

    /** 오늘 이후 필기 회차 목록 (목표 회차 선택 상자) */
    List<ExamRoundOption> findUpcomingWrittenRounds(long certificationId);

    Optional<LocalDate> findRoundStartDate(Long examRoundId);

    /** 필기 과목 목록 (이해도 입력 줄) */
    List<SubjectOption> findWrittenSubjects(long certificationId);

    /** 사용자의 가장 최근 ACTIVE 목표 */
    Optional<ActiveGoal> findActiveGoal(Long userId, long certificationId);

    /** goal_id 의 과목별 이해도 (subject_id → level) */
    Map<Long, Integer> findFamiliarity(Long goalId);

    Long insertGoal(Long userId, long certificationId, Long examRoundId, LocalDate targetExamDate,
                    String goalTitle, Integer dailyMinutes);

    void updateGoal(Long goalId, Long examRoundId, LocalDate targetExamDate, Integer dailyMinutes);

    /** 과목별 이해도 저장 (있으면 수정, 없으면 추가) */
    void saveFamiliarity(Long goalId, Long subjectId, int level);
}
