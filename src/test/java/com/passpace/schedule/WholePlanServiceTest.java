package com.passpace.schedule;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.passpace.constant.MajorType;
import com.passpace.error.ErrorCode;
import com.passpace.error.exception.BaseAppException;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.schedule.WholePlanDtos.Edit;
import com.passpace.schedule.WholePlanDtos.SubjectTime;
import com.passpace.schedule.WholePlanRepository.Item;
import com.passpace.schedule.WholePlanRepository.Placement;
import com.passpace.schedule.WholePlanRepository.Plan;
import com.passpace.schedule.WholePlanRepository.Topic;
import com.passpace.study.StudyDtos;
import com.passpace.study.StudyRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class WholePlanServiceTest {
    private final StudyRepository users = mock(StudyRepository.class);
    private final WholePlanRepository repository = mock(WholePlanRepository.class);
    private final LocalDate today = LocalDate.of(2026, 11, 24);
    private final Topic sql = new Topic(2L, "SAMPLE 시험", "SAMPLE SQL", null);
    private final Plan plan = new Plan("SAMPLE 계획", 7, today.minusDays(3), today.plusDays(14),
            "{\"2\":60,\"3\":60}");
    private final Item past = new Item(11, sql, today.minusDays(1), 20, false, false);
    private final Item recorded = new Item(12, sql, today, 45, true, false);
    private final Item movable = new Item(13, sql, today.plusDays(1), 45, false, false);
    private final Item moved = new Item(14, sql, today.plusDays(2), 15, false, true);
    private final JwtPrincipal member = new JwtPrincipal(1L, "SAMPLE", "SAMPLE", MajorType.MAJOR, "USER");
    private final WholePlanService service = new WholePlanService(users, repository,
            new ObjectMapper().findAndRegisterModules(),
            Clock.fixed(Instant.parse("2026-11-23T18:00:00Z"), ZoneOffset.UTC));

    @BeforeEach void setup() {
        when(users.findUser(eq(1L), anyBoolean())).thenReturn(Optional.of(new StudyDtos.UserState("MAJOR")));
        when(repository.plan(eq(1L), eq(2L), anyBoolean())).thenReturn(Optional.of(plan));
        when(repository.items(1, 2)).thenReturn(List.of(past, recorded, movable, moved));
    }

    private Edit edit(int version, int minutes, String approval) {
        return new Edit(version, plan.start(), plan.end(), Map.of(2, 120, 3, 120),
                List.of(new SubjectTime(11L, minutes)), approval);
    }

    @Test void readsSavedCapsAndEditableBudgetWithoutCountingProtectedItems() {
        var input = service.editor(member, 2);
        assertEquals(Map.of(2, 60, 3, 60), input.weekdayMinutes());
        assertEquals(3, input.protectedTasks());
        assertEquals(45, input.subjects().getFirst().minutes());
        assertEquals(today, input.today());
    }

    @Test void previewAndSaveRetainPlanIdProtectedRowsAndUnchangedTaskId() {
        var preview = service.preview(member, 2, edit(7, 120, null));
        assertTrue(preview.changed());
        assertEquals(3, preview.protectedTasks());
        assertTrue(preview.removed().isEmpty());
        assertEquals(today, preview.added().getFirst().date());
        assertEquals(75, preview.added().getFirst().minutes());
        verify(repository, never()).apply(anyLong(), anyLong(), any(), any(), any(), any(), any(), anyList(), anyList());

        var applied = service.apply(member, 2, edit(7, 120, preview.approval()));
        assertEquals(2, applied.planId());
        assertEquals(8, applied.planVersion());
        var ordered = inOrder(users, repository);
        ordered.verify(users).findUser(1, true);
        ordered.verify(repository).plan(1, 2, true);
        ordered.verify(repository).apply(1, 2, plan, plan.name(), plan.start(), plan.end(),
                "{\"2\":120,\"3\":120}", List.of(), List.of(new Placement(sql, today, 75)));
    }

    @Test void rejectsChangedRecordsOrRevisionWithoutWriting() {
        var preview = service.preview(member, 2, edit(7, 120, null));
        when(repository.items(1, 2)).thenReturn(List.of(past, recorded,
                new Item(movable.id(), sql, movable.date(), movable.minutes(), true, false), moved));
        assertEquals(ErrorCode.DATA_INTEGRITY_VIOLATION, assertThrows(BaseAppException.class,
                () -> service.apply(member, 2, edit(7, 120, preview.approval()))).getErrorCode());
        assertEquals(ErrorCode.DATA_INTEGRITY_VIOLATION, assertThrows(BaseAppException.class,
                () -> service.preview(member, 2, edit(6, 120, null))).getErrorCode());
        verify(repository, never()).apply(anyLong(), anyLong(), any(), any(), any(), any(), any(), anyList(), anyList());
    }

    @Test void rejectsOutOfPeriodPreservedItemsAndInsufficientCapacity() {
        var excluded = new Edit(7, today, plan.end(), Map.of(2, 120), List.of(new SubjectTime(11L, 10)), null);
        assertEquals(ErrorCode.INVALID_REQUEST, assertThrows(BaseAppException.class,
                () -> service.preview(member, 2, excluded)).getErrorCode());
        assertEquals(ErrorCode.INVALID_REQUEST, assertThrows(BaseAppException.class,
                () -> service.preview(member, 2, edit(7, 5000, null))).getErrorCode());
    }
}
