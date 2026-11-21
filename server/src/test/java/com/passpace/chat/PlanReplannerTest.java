package com.passpace.chat;

import com.passpace.service.MultiGoalPlanCalculator;
import com.passpace.service.PlanReplanner;
import com.passpace.service.PlanReplanner.PlannedTask;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/** [동건] 밀린 계획 판단과 재편성 요청 (DB 없이 계산만). */
class PlanReplannerTest {
    private static final LocalDate START = LocalDate.of(2026, 11, 2);   // 월요일

    /** 100일 동안 매일 60분: 앞 50일은 "DB", 뒤 50일은 "SQL". */
    private static List<PlannedTask> hundredDays() {
        List<PlannedTask> tasks = new ArrayList<>();
        for (int i = 0; i < 100; i++)
            tasks.add(new PlannedTask(START.plusDays(i), "SQLD", i < 50 ? "DB" : "SQL", i < 50 ? 1L : 2L, 60));
        return tasks;
    }

    @Test
    void recommendsOnlyWhenBehindByTwentyPercentOfTheWholePlan() {
        var tasks = hundredDays();
        // 19일치를 못 했을 때: 19% → 아직 추천하지 않는다.
        var nineteen = PlanReplanner.status(tasks, 0, START.plusDays(19));
        assertEquals(19 * 60, nineteen.behindMinutes());
        assertEquals(19, nineteen.behindPercent());
        assertFalse(nineteen.needed());
        // 20일치를 못 했을 때: 20% → 추천한다.
        var twenty = PlanReplanner.status(tasks, 0, START.plusDays(20));
        assertEquals(20, twenty.behindPercent());
        assertTrue(twenty.needed());
        // 30일이 지났어도 15일치를 했으면 밀린 것은 15일치(15%)뿐이다.
        assertFalse(PlanReplanner.status(tasks, 15 * 60, START.plusDays(30)).needed());
        // 계획보다 더 많이 했어도 밀린 시간은 0이다.
        assertEquals(0, PlanReplanner.status(tasks, 9000, START.plusDays(30)).behindMinutes());
        // 계획 기간이 끝난 뒤에는 다시 나눌 날이 없어 추천하지 않는다.
        assertFalse(PlanReplanner.status(tasks, 0, START.plusDays(100)).needed());
        assertFalse(PlanReplanner.status(List.of(), 0, START).needed());
    }

    @Test
    void redistributesWhatIsLeftFromTodayWithinTheOriginalPeriod() {
        var tasks = hundredDays();
        LocalDate today = START.plusDays(20);
        // DB 는 계획 50시간 중 5시간만 기록했다. SQL 은 아직 시작 전이다.
        var request = PlanReplanner.request(tasks, Map.of("SQLD|DB", 300),
                PlanReplanner.dayCaps("{\"1\":120,\"2\":120,\"3\":120,\"4\":120,\"5\":120,\"6\":120,\"7\":120}",
                        "챗봇 학습계획 (SQLD, 하루 120분)", tasks), today);
        assertNotNull(request);
        var goal = request.goals().get(0);
        assertEquals("SQLD", goal.certificationName());
        assertEquals(today, goal.startDate());
        assertEquals(START.plusDays(100), goal.examDate());
        assertEquals(45.0, goal.subjects().get(0).baseHours());   // DB: 50시간 − 5시간
        assertEquals(50.0, goal.subjects().get(1).baseHours());   // SQL: 그대로

        var plan = new MultiGoalPlanCalculator().calculate(request, today);
        assertEquals(95 * 60, plan.totalRemainingMinutes());
        assertEquals(0, plan.totalShortfallMinutes());
        assertFalse(plan.days().get(0).date().isBefore(today));
        assertTrue(plan.days().get(plan.days().size() - 1).date().isBefore(START.plusDays(100)));
        assertTrue(plan.days().stream().allMatch(d -> d.allocatedMinutes() <= 120));
        // 저장할 때 과목 ID 를 찾는 키: 목표 키 | 과목명
        assertEquals("replan|SQLD", goal.key());
    }

    @Test
    void finishedSubjectsAreLeftOutAndNothingLeftMeansNoRequest() {
        var tasks = hundredDays();
        LocalDate today = START.plusDays(20);
        var caps = Map.of(1, 120, 3, 120);
        var request = PlanReplanner.request(tasks, Map.of("SQLD|DB", 3000), caps, today);
        assertEquals(List.of("SQL"), request.goals().get(0).subjects().stream().map(s -> s.name()).toList());
        assertNull(PlanReplanner.request(tasks, Map.of("SQLD|DB", 3000, "SQLD|SQL", 3000), caps, today));
        assertNull(PlanReplanner.request(tasks, Map.of(), Map.of(), today));
    }

    @Test
    void readsDayCapsFromTheSavedColumnOrFallsBackToThePlanItself() {
        var tasks = List.of(
                new PlannedTask(LocalDate.of(2026, 11, 2), "SQLD", "DB", 1L, 88),    // 월
                new PlannedTask(LocalDate.of(2026, 11, 4), "SQLD", "DB", 1L, 50));   // 수
        assertEquals(Map.of(1, 60, 6, 240), PlanReplanner.dayCaps("{\"1\":60,\"6\":240}", "아무 이름", tasks));
        // 예전에 저장한 계획: 공부하던 요일 + 이름에 적힌 하루 시간
        assertEquals(Map.of(1, 180, 3, 180),
                PlanReplanner.dayCaps(null, "챗봇 학습계획 (SQLD, 하루 180분)", tasks));
        // 이름에도 없으면 하루에 가장 많이 배정된 시간
        assertEquals(Map.of(1, 88, 3, 88), PlanReplanner.dayCaps(null, "이름 없음", tasks));
    }
}
