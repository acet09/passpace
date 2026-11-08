package com.passpace.user.service;

import com.passpace.user.dto.GoalForm;
import com.passpace.user.dto.UserViews.ActiveGoal;
import com.passpace.user.dto.UserViews.ExamRoundOption;
import com.passpace.user.dto.UserViews.SubjectOption;
import com.passpace.user.repository.GoalRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/** [한결] 학습 목표 구현 */
@Service
public class GoalServiceImpl implements GoalService {

    private final GoalRepository goalRepository;
    private final String examCode;

    public GoalServiceImpl(GoalRepository goalRepository,
                           @Value("${passpace.certification-code}") String examCode) {
        this.goalRepository = goalRepository;
        this.examCode = examCode;
    }

    @Override
    public GoalForm getGoalForm(Long userId) {
        GoalForm form = new GoalForm();

        Optional<Long> certificationId =
                goalRepository.findCertificationId(examCode);

        if (certificationId.isEmpty()) {
            return form;
        }

        Optional<ActiveGoal> saved =
                goalRepository.findActiveGoal(userId, certificationId.get());

        if (saved.isEmpty()) {
            return form;
        }

        ActiveGoal goal = saved.get();

        form.setExamRoundId(goal.examRoundId());
        form.setTargetExamDate(goal.targetExamDate());
        form.setDailyMinutes(goal.dailyMinutes());
        form.setFamiliarity(goalRepository.findFamiliarity(goal.goalId()));

        return form;
    }

    /**
     * 목표 저장. USER_GOALS 와 GOAL_SUBJECTS 를 함께 바꾸므로 하나의 트랜잭션으로 묶는다.
     * (중간에 실패하면 둘 다 취소 → 11주차 수업의 "같은 Connection 으로 묶기"와 같은 원리)
     */
    @Override
    @Transactional
    public void saveGoal(Long userId, GoalForm form) {
        if (userId == null) {
            throw new IllegalArgumentException("다시 로그인해 주세요.");
        }
        if (form == null) {
            throw new IllegalArgumentException("목표 입력값을 확인해 주세요.");
        }

        Integer dailyMinutes = form.getDailyMinutes();
        if (dailyMinutes != null
                && (dailyMinutes < 10 || dailyMinutes > 720)) {
            throw new IllegalArgumentException(
                    "하루 가용시간은 10~720분이어야 합니다."
            );
        }

        long certificationId = goalRepository.findCertificationId(examCode)
                .orElseThrow(() -> new IllegalArgumentException(
                        "시험 기준 데이터가 없습니다. 기본 데이터 설정을 확인해 주세요."
                ));

        LocalDate targetExamDate = form.getTargetExamDate();

        if (form.getExamRoundId() != null) {
            boolean allowedRound = goalRepository
                    .findUpcomingWrittenRounds(certificationId)
                    .stream()
                    .anyMatch(round ->
                            round.examRoundId().equals(form.getExamRoundId()));

            if (!allowedRound) {
                throw new IllegalArgumentException(
                        "선택한 시험 회차를 사용할 수 없습니다. 다시 선택해 주세요."
                );
            }

            targetExamDate = goalRepository
                    .findRoundStartDate(form.getExamRoundId())
                    .orElseThrow(() -> new IllegalArgumentException(
                            "선택한 회차의 시험일을 확인할 수 없습니다."
                    ));
        }

        Map<Long, Integer> familiarity = form.getFamiliarity();
        validateFamiliarity(certificationId, familiarity);

        Optional<ActiveGoal> saved =
                goalRepository.findActiveGoal(userId, certificationId);

        Long goalId;

        if (saved.isPresent()) {
            goalId = saved.get().goalId();

            goalRepository.updateGoal(
                    goalId,
                    form.getExamRoundId(),
                    targetExamDate,
                    dailyMinutes
            );
        } else {
            goalId = goalRepository.insertGoal(
                    userId,
                    certificationId,
                    form.getExamRoundId(),
                    targetExamDate,
                    "필기 합격 목표",
                    dailyMinutes
            );
        }

        if (familiarity != null) {
            for (Map.Entry<Long, Integer> entry : familiarity.entrySet()) {
                if (entry.getValue() != null) {
                    goalRepository.saveFamiliarity(
                            goalId, entry.getKey(), entry.getValue()
                    );
                }
            }
        }
    }

    @Override
    public List<ExamRoundOption> getExamRoundOptions() {
        Optional<Long> certificationId =
                goalRepository.findCertificationId(examCode);

        if (certificationId.isEmpty()) {
            return List.of();
        }

        return goalRepository.findUpcomingWrittenRounds(certificationId.get());
    }

    @Override
    public List<SubjectOption> getSubjects() {
        Optional<Long> certificationId =
                goalRepository.findCertificationId(examCode);

        if (certificationId.isEmpty()) {
            return List.of();
        }

        return goalRepository.findWrittenSubjects(certificationId.get());
    }

    private void validateFamiliarity(
            long certificationId, Map<Long, Integer> familiarity) {
        if (familiarity == null || familiarity.isEmpty()) {
            return;
        }

        List<SubjectOption> subjects =
                goalRepository.findWrittenSubjects(certificationId);

        for (Map.Entry<Long, Integer> entry : familiarity.entrySet()) {
            if (entry.getValue() == null) {
                continue;
            }

            boolean allowedSubject = subjects.stream()
                    .anyMatch(subject ->
                            subject.subjectId().equals(entry.getKey()));

            if (!allowedSubject) {
                throw new IllegalArgumentException(
                        "올바른 필기 과목을 선택해 주세요."
                );
            }

            int level = entry.getValue();

            if (level < 1 || level > 3) {
                throw new IllegalArgumentException(
                        "과목별 이해도는 1~3 중에서 선택해 주세요."
                );
            }
        }
    }
}