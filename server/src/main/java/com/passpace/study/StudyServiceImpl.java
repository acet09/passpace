package com.passpace.study;

import com.passpace.constant.MajorType;
import com.passpace.error.ErrorCode;
import com.passpace.study.StudyDtos.DailyStudyMinutes;
import com.passpace.study.StudyDtos.DayTotal;
import com.passpace.study.StudyDtos.PlanTask;
import com.passpace.study.StudyDtos.SaveSessionRequest;
import com.passpace.study.StudyDtos.SessionPageResponse;
import com.passpace.study.StudyDtos.SessionResponse;
import com.passpace.study.StudyDtos.SessionRow;
import com.passpace.study.StudyDtos.StudyException;
import com.passpace.study.StudyDtos.StudyStatsResponse;
import com.passpace.study.StudyDtos.UpdateSessionRequest;
import com.passpace.study.StudyDtos.DeleteSessionRequest;
import com.passpace.study.StudyDtos.DeleteSessionResponse;
import com.passpace.study.StudyDtos.PlanTaskPageResponse;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.dao.TransientDataAccessException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Objects;

/**
 * [한결] 실제 공부시간 기록·조회·통계의 업무 규칙과 트랜잭션.
 *
 * <p>새 기록 작성자끼리는 사용자 행 잠금으로 직렬화한다. 연결된 계획도 잠그고
 * 버전을 확인하지만 기존 계획 작성자가 동일한 잠금 규약에 참여한다고 가정하지 않는다.
 * 이 클래스는 기존 계획 승인·재편성이나 진행률·과목 이해도를 변경하지 않는다.
 */
@Service
public class StudyServiceImpl implements StudyService {
    private static final ZoneId SEOUL = ZoneId.of("Asia/Seoul");
    private static final int MAX_DAILY_MINUTES = 1440;
    private static final int MAX_RANGE_DAYS = 366;
    private final StudyRepository repository;
    private final Clock clock;

    public StudyServiceImpl(StudyRepository repository, ObjectProvider<Clock> clocks) {
        this.repository = repository;
        this.clock = clocks.getIfAvailable(Clock::systemUTC);
    }

    @Override
    @Transactional
    public SessionResponse save(long userId, MajorType authenticatedMajor, SaveSessionRequest request) {
        validateRequest(request);
        try {
            verifyUser(userId, authenticatedMajor, true);
            PlanTask task = request.taskId() == null ? null : ownedTask(userId, request);
            List<DayTotal> current = repository.findDailyTotals(userId, request.studyDate(), request.studyDate());
            long alreadyRecorded = 0;
            for (DayTotal day : current) {
                validateDay(day);
                alreadyRecorded = Math.addExact(alreadyRecorded, day.durationMinutes());
            }
            if (alreadyRecorded + request.durationMinutes() > MAX_DAILY_MINUTES)
                throw conflict("같은 날짜의 실제 공부시간 합계는 24시간을 넘을 수 없습니다.");
            long id = repository.insert(userId, request.taskId(), request.studyDate(), request.durationMinutes());
            return new SessionResponse(id, request.studyDate(), request.durationMinutes(), request.taskId(),
                    task == null ? null : task.planId(), task == null ? null : task.subjectId(),
                    task == null ? null : task.subjectName(), "MANUAL");
        } catch (TransientDataAccessException e) {
            throw conflict("다른 저장 작업과 겹쳤습니다. 기록 목록을 확인한 뒤 다시 시도해 주세요.");
        }
    }

    @Override
    @Transactional
    public SessionResponse update(long userId, MajorType authenticatedMajor, long sessionId,
                                   UpdateSessionRequest request) {
        if (sessionId <= 0 || request == null) throw invalid("수정할 학습기록을 확인해 주세요.");
        // Date/minute validation is shared with create; explicit link changes are checked under the user lock.
        validateRequest(new SaveSessionRequest(request.studyDate(), request.durationMinutes(),
                null, null, null, null));
        validateDate(request.expectedStudyDate());
        if (request.expectedDurationMinutes() == null || request.expectedDurationMinutes() < 1 ||
                request.expectedDurationMinutes() > MAX_DAILY_MINUTES)
            throw invalid("조회한 기록의 원래 날짜와 공부시간을 함께 보내 주세요.");
        var link = request.taskLink();
        if (request.expectedTask() != null && request.expectedTask().taskId() != null && request.expectedTask().taskId() <= 0)
            throw invalid("기존 계획 항목 ID는 양수 또는 null로 입력해 주세요.");
        if (link != null && (link.taskId() != null && link.taskId() <= 0 ||
                link.expectedTaskId() != null && link.expectedTaskId() <= 0))
            throw invalid("계획 항목 ID는 양수 또는 null로 입력해 주세요.");
        try {
            verifyUser(userId, authenticatedMajor, true);
            SessionRow current = repository.findOwnedSessionForUpdate(userId, sessionId)
                    .orElseThrow(() -> new StudyException(ErrorCode.FORBIDDEN_ACCESS,
                            "이 학습기록을 수정할 수 없습니다."));
            if (current.studyDate() == null || current.durationMinutes() == null ||
                    current.durationMinutes() < 1 || current.durationMinutes() > MAX_DAILY_MINUTES ||
                    current.invalidLink()) throw unavailable();
            if (!"MANUAL".equals(current.inputMethod()))
                throw conflict("직접 입력한 학습기록만 수정할 수 있습니다.");
            if (!current.studyDate().equals(request.expectedStudyDate()) ||
                    !current.durationMinutes().equals(request.expectedDurationMinutes()))
                throw conflict("이 기록이 다른 곳에서 변경됐습니다. 목록을 다시 확인한 뒤 수정해 주세요.");
            Long nextTaskId = current.taskId();
            if (request.expectedTask() != null && !Objects.equals(current.taskId(), request.expectedTask().taskId()))
                throw conflict("과목 연결이 변경됐습니다. 목록을 다시 확인한 뒤 수정해 주세요.");
            Long nextPlanId = current.planId(), nextSubjectId = current.subjectId();
            String nextSubjectName = current.subjectName();
            if (link != null) {
                if (!Objects.equals(current.taskId(), link.expectedTaskId()))
                    throw conflict("과목 연결이 변경됐습니다. 목록을 다시 확인한 뒤 수정해 주세요.");
                nextTaskId = link.taskId();
                if (nextTaskId == null) {
                    if (link.expectedPlanVersion() != null)
                        throw invalid("연결 해제 시 계획 버전을 보내지 마세요.");
                    nextPlanId = null; nextSubjectId = null; nextSubjectName = null;
                } else {
                    SaveSessionRequest selection = new SaveSessionRequest(request.studyDate(), request.durationMinutes(),
                            nextTaskId, link.expectedPlanVersion(), null, null);
                    validateRequest(selection);
                    PlanTask selected = ownedTask(userId, selection);
                    nextPlanId = selected.planId(); nextSubjectId = selected.subjectId();
                    nextSubjectName = selected.subjectName();
                }
            }
            long otherMinutes = 0;
            for (DayTotal day : repository.findDailyTotals(userId, request.studyDate(), request.studyDate())) {
                validateDay(day);
                otherMinutes = Math.addExact(otherMinutes, day.durationMinutes());
            }
            if (current.studyDate().equals(request.studyDate()))
                otherMinutes -= current.durationMinutes();
            if (otherMinutes < 0) throw unavailable();
            if (otherMinutes + request.durationMinutes() > MAX_DAILY_MINUTES)
                throw conflict("같은 날짜의 실제 공부시간 합계는 24시간을 넘을 수 없습니다.");
            boolean unchanged = current.studyDate().equals(request.studyDate()) &&
                    current.durationMinutes().equals(request.durationMinutes()) && Objects.equals(current.taskId(), nextTaskId);
            if (!unchanged && repository.updateOwnedSession(userId, sessionId, request.studyDate(),
                    request.durationMinutes(), current.studyDate(), current.durationMinutes(), nextTaskId, current.taskId()) != 1)
                throw conflict("이 기록이 변경됐습니다. 목록을 다시 확인한 뒤 수정해 주세요.");
            return new SessionResponse(current.sessionId(), request.studyDate(), request.durationMinutes(),
                    nextTaskId, nextPlanId, nextSubjectId, nextSubjectName, current.inputMethod());
        } catch (TransientDataAccessException e) {
            throw conflict("다른 저장 작업과 겹쳤습니다. 기록 목록을 확인한 뒤 다시 시도해 주세요.");
        }
    }

    @Override
    @Transactional
    public DeleteSessionResponse delete(long userId, MajorType authenticatedMajor, long sessionId,
                                         DeleteSessionRequest request) {
        if (sessionId <= 0 || request == null) throw invalid("삭제할 기록을 확인해 주세요.");
        validateDate(request.expectedStudyDate());
        if (request.expectedDurationMinutes() == null || request.expectedDurationMinutes() < 1 ||
                request.expectedDurationMinutes() > MAX_DAILY_MINUTES ||
                request.expectedTaskId() != null && request.expectedTaskId() <= 0)
            throw invalid("조회한 기록의 날짜·공부시간·과목 연결을 확인해 주세요.");
        try {
            verifyUser(userId, authenticatedMajor, true);
            SessionRow current = repository.findOwnedSessionForUpdate(userId, sessionId)
                    .orElseThrow(() -> new StudyException(ErrorCode.FORBIDDEN_ACCESS,"이 학습기록을 삭제할 수 없습니다."));
            if (current.studyDate() == null || current.durationMinutes() == null ||
                    current.durationMinutes() < 1 || current.durationMinutes() > MAX_DAILY_MINUTES || current.invalidLink())
                throw unavailable();
            if (!"MANUAL".equals(current.inputMethod())) throw conflict("직접 입력한 기록만 삭제할 수 있습니다.");
            if (!current.studyDate().equals(request.expectedStudyDate()) ||
                    !current.durationMinutes().equals(request.expectedDurationMinutes()) ||
                    !Objects.equals(current.taskId(), request.expectedTaskId()))
                throw conflict("이 기록이 변경됐습니다. 목록을 다시 확인한 뒤 삭제해 주세요.");
            if (repository.deleteOwnedSession(userId, sessionId, current.studyDate(), current.durationMinutes(), current.taskId()) != 1)
                throw conflict("이 기록이 변경됐습니다. 목록을 다시 확인한 뒤 삭제해 주세요.");
            return new DeleteSessionResponse(sessionId, true);
        } catch (TransientDataAccessException e) {
            throw conflict("다른 저장 작업과 겹쳤습니다. 기록 목록을 확인한 뒤 다시 시도해 주세요.");
        }
    }

    @Override
    @Transactional(readOnly = true)
    public PlanTaskPageResponse planTasks(long userId, MajorType authenticatedMajor, LocalDate date,
                                          boolean includeReplaced, int page, int pageSize) {
        if (date != null) validateDate(date);
        if (page < 0 || page > 10000 || pageSize < 1 || pageSize > 100)
            throw invalid("페이지는0~10000, 페이지 크기는1~100으로 입력해 주세요.");
        verifyUser(userId, authenticatedMajor, false);
        var items = repository.findOwnedPlanTasks(userId, date, includeReplaced, pageSize + 1, (long)page * pageSize);
        return new PlanTaskPageResponse(items.subList(0, Math.min(pageSize, items.size())), page, pageSize, items.size() > pageSize);
    }

    @Override
    @Transactional(readOnly = true)
    public SessionPageResponse findSessions(long userId, MajorType authenticatedMajor,
                                             LocalDate startDate, LocalDate endDate, int page, int pageSize) {
        validateRange(startDate, endDate);
        if (page < 0 || page > 10000 || pageSize < 1 || pageSize > 100)
            throw invalid("페이지는 0~10000, 페이지 크기는 1~100으로 입력해 주세요.");
        verifyUser(userId, authenticatedMajor, false);
        List<SessionRow> rows = repository.findSessions(userId, startDate, endDate,
                pageSize + 1, (long) page * pageSize);
        boolean hasNext = rows.size() > pageSize;
        List<SessionResponse> items = new ArrayList<>();
        for (SessionRow row : rows.subList(0, Math.min(pageSize, rows.size()))) {
            if (row.studyDate() == null || row.durationMinutes() == null || row.durationMinutes() <= 0 ||
                    row.durationMinutes() > MAX_DAILY_MINUTES || row.invalidLink())
                throw unavailable();
            items.add(new SessionResponse(row.sessionId(), row.studyDate(), row.durationMinutes(),
                    row.taskId(), row.planId(), row.subjectId(), row.subjectName(), row.inputMethod()));
        }
        return new SessionPageResponse(items, page, pageSize, hasNext);
    }

    @Override
    @Transactional(readOnly = true)
    public StudyStatsResponse getStats(long userId, MajorType authenticatedMajor,
                                       String period, LocalDate startDate, LocalDate endDate) {
        String selected = period == null ? "LAST_7_DAYS" : period.trim().toUpperCase(Locale.ROOT);
        LocalDate today = LocalDate.now(clock.withZone(SEOUL));
        if ("CUSTOM".equals(selected)) {
            validateRange(startDate, endDate);
        } else if ("LAST_7_DAYS".equals(selected) || "LAST_30_DAYS".equals(selected)) {
            if (startDate != null || endDate != null)
                throw invalid("날짜를 직접 지정하려면 period=CUSTOM을 사용해 주세요.");
            startDate = today.minusDays("LAST_7_DAYS".equals(selected) ? 6 : 29);
            endDate = today;
        } else {
            throw invalid("기간은 LAST_7_DAYS, LAST_30_DAYS, CUSTOM 중에서 선택해 주세요.");
        }
        verifyUser(userId, authenticatedMajor, false);
        var byDate = new HashMap<LocalDate, Long>();
        long total = 0;
        for (DayTotal day : repository.findDailyTotals(userId, startDate, endDate)) {
            validateDay(day);
            byDate.put(day.studyDate(), day.durationMinutes());
            total = Math.addExact(total, day.durationMinutes());
        }
        List<DailyStudyMinutes> daily = new ArrayList<>();
        for (LocalDate date = startDate; !date.isAfter(endDate); date = date.plusDays(1))
            daily.add(new DailyStudyMinutes(date, byDate.getOrDefault(date, 0L)));
        return new StudyStatsResponse(selected, startDate, endDate, SEOUL.getId(), total, daily, null);
    }

    private void verifyUser(long userId, MajorType authenticatedMajor, boolean lock) {
        if (userId <= 0)
            throw new StudyException(ErrorCode.FAILURE_JWT_VERIFIED, "다시 로그인해 주세요.");
        var user = repository.findUser(userId, lock).orElseThrow(() ->
                new StudyException(ErrorCode.FAILURE_JWT_VERIFIED, "다시 로그인해 주세요."));
        MajorType currentMajor = MajorType.fromCode(user.majorCode());
        if (currentMajor == null || authenticatedMajor == null)
            throw new StudyException(ErrorCode.MISSING_MAJOR, "전공 구분을 설정하고 다시 로그인해 주세요.");
        if (currentMajor != authenticatedMajor)
            throw new StudyException(ErrorCode.FORBIDDEN_ACCESS, "회원정보가 변경됐습니다. 다시 로그인해 주세요.");
    }

    private PlanTask ownedTask(long userId, SaveSessionRequest request) {
        PlanTask task = repository.findOwnedTaskForUpdate(userId, request.taskId())
                .orElseThrow(() -> new StudyException(ErrorCode.FORBIDDEN_ACCESS,
                        "이 학습계획 항목을 사용할 수 없습니다."));
        if (task.planVersion() == null || !Objects.equals(task.planVersion(), request.expectedPlanVersion()) ||
                (!"ACTIVE".equals(task.planStatus()) && !"REPLACED".equals(task.planStatus())))
            throw conflict("계획 상태나 버전이 달라졌습니다. 저장된 계획을 다시 확인해 주세요.");
        if (request.planId() != null && request.planId() != task.planId())
            throw invalid("선택한 항목과 계획이 일치하지 않습니다.");
        if (request.subjectId() != null && !Objects.equals(request.subjectId(), task.subjectId()))
            throw invalid("선택한 항목과 과목이 일치하지 않습니다.");
        return task;
    }

    private void validateRequest(SaveSessionRequest request) {
        if (request == null) throw invalid("학습기록을 입력해 주세요.");
        validateDate(request.studyDate());
        if (request.studyDate().isAfter(LocalDate.now(clock.withZone(SEOUL))))
            throw invalid("실제 공부한 날짜는 오늘 이후로 저장할 수 없습니다.");
        if (request.durationMinutes() == null || request.durationMinutes() < 1 ||
                request.durationMinutes() > MAX_DAILY_MINUTES)
            throw invalid("실제 공부시간은 정수 1~1440분으로 입력해 주세요.");
        if (request.taskId() != null && request.taskId() <= 0 ||
                request.subjectId() != null && request.subjectId() <= 0 ||
                request.planId() != null && request.planId() <= 0 ||
                request.expectedPlanVersion() != null && request.expectedPlanVersion() <= 0)
            throw invalid("식별자와 계획 버전은 양수로 입력해 주세요.");
        if (request.taskId() == null && (request.subjectId() != null || request.planId() != null ||
                request.expectedPlanVersion() != null))
            throw invalid("과목이나 계획에 연결하려면 taskId를 선택해 주세요.");
        if (request.taskId() != null && request.expectedPlanVersion() == null)
            throw invalid("계획 항목의 expectedPlanVersion을 함께 입력해 주세요.");
    }

    private static void validateRange(LocalDate startDate, LocalDate endDate) {
        validateDate(startDate);
        validateDate(endDate);
        long days = ChronoUnit.DAYS.between(startDate, endDate) + 1;
        if (days < 1 || days > MAX_RANGE_DAYS)
            throw invalid("조회 시작일과 종료일을 포함해 1~366일 범위로 입력해 주세요.");
    }

    private static void validateDate(LocalDate date) {
        if (date == null || date.getYear() < 1000 || date.getYear() > 9999)
            throw invalid("날짜를 YYYY-MM-DD 형식의 유효한 값으로 입력해 주세요.");
    }

    private static void validateDay(DayTotal day) {
        if (day.studyDate() == null || day.invalidRecords() != 0 ||
                day.durationMinutes() < 0 || day.durationMinutes() > MAX_DAILY_MINUTES)
            throw unavailable();
    }

    private static StudyException invalid(String detail) {
        return new StudyException(ErrorCode.INVALID_REQUEST, detail);
    }

    private static StudyException conflict(String detail) {
        return new StudyException(ErrorCode.DATA_INTEGRITY_VIOLATION, detail);
    }

    private static StudyException unavailable() {
        return new StudyException(ErrorCode.SERVICE_UNAVAILABLE,
                "기존 학습기록의 시간 또는 연결 정보를 확인해야 합니다.");
    }
}
