package com.passpace.schedule;

import com.passpace.constant.MajorType;
import com.passpace.error.ErrorCode;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.schedule.PlanScheduleDtos.Change;
import com.passpace.schedule.PlanScheduleDtos.Period;
import com.passpace.schedule.PlanScheduleDtos.PeriodUpdated;
import com.passpace.schedule.PlanScheduleDtos.ScheduleException;
import com.passpace.schedule.PlanScheduleDtos.Updated;
import com.passpace.study.StudyRepository;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.TransientDataAccessException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.ZoneId;

/** [한결] 저장된 학습계획의 항목 날짜와 분을 수정한다. */
@Service
public class PlanScheduleService {
    private static final ZoneId SEOUL = ZoneId.of("Asia/Seoul");
    private static final int DAILY_LIMIT = 960;
    private final StudyRepository users;
    private final PlanScheduleRepository schedules;
    private final Clock clock;

    @Autowired
    public PlanScheduleService(StudyRepository users, PlanScheduleRepository schedules, ObjectProvider<Clock> clocks) {
        this(users, schedules, clocks.getIfAvailable(Clock::systemUTC));
    }

    PlanScheduleService(StudyRepository users, PlanScheduleRepository schedules, Clock clock) {
        this.users = users;
        this.schedules = schedules;
        this.clock = clock;
    }

    @Transactional
    public Updated change(JwtPrincipal member, long planId, long taskId, Change request) {
        long userId = requireIdentity(member);
        if (planId < 1 || taskId < 1 || request == null || request.expectedPlanVersion() == null ||
                request.expectedPlanVersion() < 1 ||
                (request.scheduledDate() == null && request.estimatedMinutes() == null)) {
            throw invalid("일정과 수정할 날짜 또는 배정 시간을 확인해 주세요.");
        }
        try {
            verifyMember(member, userId);
            var entry = schedules.lockEntry(userId, planId, taskId).orElseThrow(() ->
                    new ScheduleException(ErrorCode.NOT_FOUND_ENDPOINT, "수정할 학습 항목을 찾을 수 없어요."));
            if (entry.version() != request.expectedPlanVersion()) {
                throw conflict("계획이 바뀌었어요. 최신 일정을 확인해 주세요.");
            }
            LocalDate today = LocalDate.now(clock.withZone(SEOUL));
            if (entry.date() == null || entry.date().isBefore(today) || entry.minutes() < 1 ||
                    entry.start() == null || entry.end() == null) {
                throw conflict("이미 지난 일정이나 배정 정보가 없는 항목은 수정할 수 없어요.");
            }
            LocalDate date = request.scheduledDate() == null ? entry.date() : request.scheduledDate();
            int minutes = request.estimatedMinutes() == null ? entry.minutes() : request.estimatedMinutes();
            if (date.isBefore(today) || date.isBefore(entry.start()) || date.isAfter(entry.end())) {
                throw invalid("계획 기간 안에서 오늘 이후 날짜를 선택해 주세요.");
            }
            if (minutes < 1 || minutes > DAILY_LIMIT) {
                throw invalid("배정 시간은 정수 1~960분으로 입력해 주세요.");
            }
            if (date.equals(entry.date()) && minutes == entry.minutes()) {
                return new Updated(planId, taskId, entry.version(), date, minutes);
            }

            long recorded = schedules.savedMinutes(userId, taskId, entry.date());
            if (recorded >= entry.minutes()) {
                throw conflict("배정 시간을 채운 학습 항목은 그대로 보관해요.");
            }
            if (date.equals(entry.date()) && minutes < recorded) {
                throw invalid("배정 시간은 이미 기록한 공부시간보다 짧을 수 없어요.");
            }
            if (schedules.otherPlannedMinutes(userId, planId, taskId, date) + minutes > DAILY_LIMIT) {
                throw invalid("한 날짜의 배정 시간 합계는 960분까지예요.");
            }
            int version = schedules.update(userId, planId, taskId, entry.date(), date, minutes, entry.version());
            return new Updated(planId, taskId, version, date, minutes);
        } catch (TransientDataAccessException e) {
            throw conflict("다른 저장과 겹쳤어요. 최신 일정을 확인해 주세요.");
        }
    }

    @Transactional
    public PeriodUpdated changePeriod(JwtPrincipal member, long planId, Period request) {
        long userId = requireIdentity(member);
        if (planId < 1 || request == null || request.expectedPlanVersion() == null ||
                request.expectedPlanVersion() < 1 || request.startDate() == null || request.endDate() == null ||
                request.endDate().isBefore(request.startDate())) {
            throw invalid("시작일은 종료일과 같거나 더 빨라야 해요.");
        }
        try {
            verifyMember(member, userId);
            var current = schedules.lockPeriod(userId, planId).orElseThrow(() ->
                    new ScheduleException(ErrorCode.NOT_FOUND_ENDPOINT, "수정할 계획을 찾을 수 없어요."));
            if (current.version() != request.expectedPlanVersion()) {
                throw conflict("계획이 바뀌었어요. 최신 일정을 확인해 주세요.");
            }
            LocalDate start = request.startDate();
            LocalDate end = request.endDate();
            LocalDate today = LocalDate.now(clock.withZone(SEOUL));
            LocalDate limit = today.plusDays(540);
            if (outsideEditableRange(start, current.start(), today, limit) ||
                    outsideEditableRange(end, current.end(), today, limit)) {
                throw invalid("새 시작일과 종료일은 오늘부터 540일 이내로 입력해 주세요.");
            }
            if ((current.firstTask() != null && start.isAfter(current.firstTask())) ||
                    (current.lastTask() != null && end.isBefore(current.lastTask()))) {
                throw invalid("변경한 기간 밖에 학습 항목이 있어요. 해당 항목을 먼저 옮겨 주세요.");
            }
            int version = current.version();
            if (!start.equals(current.start()) || !end.equals(current.end())) {
                version = schedules.updatePeriod(userId, planId, start, end, version);
            }
            return new PeriodUpdated(planId, version, start, end);
        } catch (TransientDataAccessException e) {
            throw conflict("다른 저장과 겹쳤어요. 최신 일정을 확인해 주세요.");
        }
    }

    private static boolean outsideEditableRange(LocalDate value, LocalDate original, LocalDate today, LocalDate limit) {
        return !value.equals(original) && (value.isBefore(today) || value.isAfter(limit));
    }

    private static long requireIdentity(JwtPrincipal member) {
        if (member == null || member.getUserId() == null || member.getUserId() < 1) {
            throw new ScheduleException(ErrorCode.FAILURE_JWT_VERIFIED, "다시 로그인해 주세요.");
        }
        return member.getUserId();
    }

    private void verifyMember(JwtPrincipal member, long userId) {
        var user = users.findUser(userId, true).orElseThrow(() ->
                new ScheduleException(ErrorCode.FAILURE_JWT_VERIFIED, "다시 로그인해 주세요."));
        if (member.getMajorType() == null || MajorType.fromCode(user.majorCode()) != member.getMajorType()) {
            throw new ScheduleException(ErrorCode.FORBIDDEN_ACCESS, "회원정보가 바뀌었어요. 다시 로그인해 주세요.");
        }
    }

    private static ScheduleException invalid(String text) {
        return new ScheduleException(ErrorCode.INVALID_REQUEST, text);
    }

    private static ScheduleException conflict(String text) {
        return new ScheduleException(ErrorCode.DATA_INTEGRITY_VIOLATION, text);
    }
}
