package com.passpace.schedule;

import com.passpace.constant.MajorType;
import com.passpace.error.ErrorCode;
import com.passpace.error.exception.BaseAppException;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.schedule.PlanScheduleDtos.Change;
import com.passpace.schedule.PlanScheduleDtos.Period;
import com.passpace.schedule.PlanScheduleRepository.Entry;
import com.passpace.schedule.PlanScheduleRepository.PlanWindow;
import com.passpace.study.StudyDtos;
import com.passpace.study.StudyRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class PlanScheduleServiceTest {
    private final StudyRepository users = mock(StudyRepository.class);
    private final PlanScheduleRepository schedules = mock(PlanScheduleRepository.class);
    private final Clock clock = Clock.fixed(Instant.parse("2026-11-21T16:00:00Z"), ZoneOffset.UTC);
    private final LocalDate today = LocalDate.of(2026, 11, 22);
    private final PlanScheduleService service = new PlanScheduleService(users, schedules, clock);
    private final JwtPrincipal member = new JwtPrincipal(1L, "SAMPLE", "SAMPLE", MajorType.MAJOR, "USER");

    @BeforeEach void setup() {
        when(users.findUser(1, true)).thenReturn(Optional.of(new StudyDtos.UserState("MAJOR")));
        when(schedules.lockEntry(1, 2, 3)).thenReturn(Optional.of(entry(today, 7)));
    }

    private Entry entry(LocalDate date, int version) {
        return new Entry(version, today.minusDays(2), today.plusDays(6), date, 90);
    }

    @Test void movingKeepsTheSameTaskAndCurrentAllocation() {
        var date = today.plusDays(1);
        when(schedules.update(1, 2, 3, today, date, 90, 7)).thenReturn(8);
        var result = service.change(member, 2, 3, new Change(7, date, null));
        assertEquals(8, result.planVersion());
        assertEquals(3L, result.taskId());
        assertEquals(date, result.scheduledDate());
        assertEquals(90, result.estimatedMinutes());
        var sequence = inOrder(users, schedules);
        sequence.verify(users).findUser(1, true);
        sequence.verify(schedules).lockEntry(1, 2, 3);
    }

    @Test void staleOrForeignTasksNeverMutate() {
        assertCode(ErrorCode.DATA_INTEGRITY_VIOLATION, 3, new Change(6, today, 120));
        assertCode(ErrorCode.NOT_FOUND_ENDPOINT, 11, new Change(7, today, 120));
        verify(schedules, never()).update(anyLong(), anyLong(), anyLong(), any(), any(), anyInt(), anyInt());
    }

    @Test void rejectsPastCompletedAndOverloadedAssignments() {
        when(schedules.lockEntry(1, 2, 3)).thenReturn(Optional.of(entry(today.minusDays(1), 7)));
        assertCode(ErrorCode.DATA_INTEGRITY_VIOLATION, 3, new Change(7, today, 120));
        when(schedules.lockEntry(1, 2, 3)).thenReturn(Optional.of(entry(today, 7)));
        when(schedules.savedMinutes(1, 3, today)).thenReturn(90L);
        assertCode(ErrorCode.DATA_INTEGRITY_VIOLATION, 3, new Change(7, today.plusDays(2), 120));
        when(schedules.savedMinutes(1, 3, today)).thenReturn(20L);
        when(schedules.otherPlannedMinutes(1, 2, 3, today)).thenReturn(900L);
        assertCode(ErrorCode.INVALID_REQUEST, 3, new Change(7, null, 120));
        assertCode(ErrorCode.INVALID_REQUEST, 3, new Change(7, today.plusDays(7), null));
        verify(schedules, never()).update(anyLong(), anyLong(), anyLong(), any(), any(), anyInt(), anyInt());
    }

    private void assertCode(ErrorCode expected, long taskId, Change change) {
        assertEquals(expected, assertThrows(BaseAppException.class,
                () -> service.change(member, 2, taskId, change)).getErrorCode());
    }

    @Test void changingThePeriodRetainsExistingEntriesIncludingPastOnes() {
        var start = today.minusDays(3);
        var end = today.plusDays(6);
        var later = end.plusDays(2);
        when(schedules.lockPeriod(1, 2)).thenReturn(Optional.of(
                new PlanWindow(7, start, end, start.plusDays(1), end)));
        when(schedules.updatePeriod(1, 2, start, later, 7)).thenReturn(8);
        var result = service.changePeriod(member, 2, new Period(7, start, later));
        assertEquals(later, result.endDate());
        assertEquals(8, result.planVersion());
        assertEquals(ErrorCode.INVALID_REQUEST, assertThrows(BaseAppException.class,
                () -> service.changePeriod(member, 2, new Period(7, today, end))).getErrorCode());
        assertEquals(ErrorCode.INVALID_REQUEST, assertThrows(BaseAppException.class,
                () -> service.changePeriod(member, 2, new Period(7, start, end.minusDays(1)))).getErrorCode());
        verify(schedules, times(1)).updatePeriod(anyLong(), anyLong(), any(), any(), anyInt());
    }
    
    @Test void periodRejectsStaleVersion() {
        when(schedules.lockPeriod(1, 2)).thenReturn(Optional.of(
                new PlanWindow(9, today, today.plusDays(2), today, today.plusDays(1))));
        assertEquals(ErrorCode.DATA_INTEGRITY_VIOLATION, assertThrows(BaseAppException.class,
                () -> service.changePeriod(member, 2, new Period(8, today, today.plusDays(3)))).getErrorCode());
        verify(schedules, never()).updatePeriod(anyLong(), anyLong(), any(), any(), anyInt());
    }
}
