package com.passpace.chat;

import com.passpace.service.MultiGoalPlanCalculator;
import com.passpace.service.MultiGoalPlanCalculator.*;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/** [동건] 통합 계획 기능 추가 테스트. 기존 ChatLogicTest는 수정하지 않는다. */
class MultiGoalPlanCalculatorTest {
    private static final LocalDate TODAY = LocalDate.of(2026, 11, 7);
    private final MultiGoalPlanCalculator calculator = new MultiGoalPlanCalculator();

    private SubjectInput sub(String name, double hours, int level, int progress, int spent) {
        return new SubjectInput(name, hours, level, progress, spent);
    }
    private GoalInput goal(String id, int days, SubjectInput... subs) {
        return new GoalInput(id, id, TODAY.plusDays(days), List.of(subs));
    }

    @Test
    void differentDeadlinesSharedDailyCapacity() {
        var plan = calculator.calculate(new PlanRequest(180, List.of(
                goal("정보처리기사", 10, sub("개발", 10, 1, 0, 0), sub("DB", 10, 3, 0, 0)),
                goal("SQLD", 15, sub("모델링", 5, 2, 0, 0)))), TODAY);
        assertEquals(1500, plan.totalRemainingMinutes());
        assertTrue(plan.feasible());
        assertEquals(10, plan.goals().get(0).remainingDays());
        assertEquals(15, plan.goals().get(1).remainingDays());
        assertTrue(plan.days().stream().allMatch(day -> day.allocatedMinutes() <= day.availableMinutes()));
        assertTrue(plan.days().stream().anyMatch(day -> day.allocations().stream()
                .map(Allocation::goalKey).distinct().count() == 2));
    }

    @Test
    void familiarityIsExplicitAndAppliesExactWeights() {
        var plan = calculator.calculate(new PlanRequest(180, List.of(
                goal("A", 10, sub("낮음", 10, 1, 0, 0),
                        sub("보통", 10, 2, 0, 0), sub("높음", 10, 3, 0, 0)))), TODAY);
        assertEquals(1800, plan.totalRemainingMinutes()); // (13 + 10 + 7) hours
        assertEquals(1.3, plan.goals().get(0).subjects().get(0).weight());
        assertEquals(0.7, plan.goals().get(0).subjects().get(2).weight());
    }

    @Test
    void shortageHasActionableDailyIncrease() {
        var plan = calculator.calculate(new PlanRequest(30, List.of(
                goal("A", 5, sub("a", 10, 2, 0, 0)),
                goal("B", 10, sub("b", 10, 2, 0, 0)))), TODAY);
        assertFalse(plan.feasible());
        assertTrue(plan.totalShortfallMinutes() > 0);
        assertTrue(plan.minimumDailyMinutes() > 30);
        assertEquals(plan.minimumDailyMinutes() - 30, plan.additionalDailyMinutes());
    }

    @Test
    void slowerLearningRaisesRemainingForecast() {
        var baseline = calculator.calculate(new PlanRequest(180, List.of(
                goal("A", 15, sub("a", 10, 1, 50, 0)))), TODAY);
        var slower = calculator.calculate(new PlanRequest(180, List.of(
                goal("A", 15, sub("a", 10, 1, 50, 600)))), TODAY);
        assertTrue(slower.totalRemainingMinutes() > baseline.totalRemainingMinutes());
    }

    @Test
    void fasterLearningLowersRemainingForecast() {
        var baseline = calculator.calculate(new PlanRequest(180, List.of(
                goal("A", 15, sub("a", 10, 1, 50, 0)))), TODAY);
        var faster = calculator.calculate(new PlanRequest(180, List.of(
                goal("A", 15, sub("a", 10, 1, 50, 180)))), TODAY);
        assertTrue(faster.totalRemainingMinutes() < baseline.totalRemainingMinutes());
    }

    @Test
    void daysPassedWithoutProgressRecalculateDeadline() {
        var req = new PlanRequest(120, List.of(goal("A", 7, sub("a", 12, 1, 0, 0))));
        var before = calculator.calculate(req, TODAY);
        var later = calculator.calculate(req, TODAY.plusDays(3));
        assertEquals(before.goals().get(0).remainingDays() - 3,
                later.goals().get(0).remainingDays());
    }

    @Test
    void notSelectedFamiliarityCannotBeInferred() {
        var request = new PlanRequest(120, List.of(
                goal("A", 10, new SubjectInput("a", 10.0, null, 0, 0))));
        assertThrows(IllegalArgumentException.class, () -> calculator.calculate(request, TODAY));
    }

    @Test
    void missingBaseHoursMustNotBeInvented() {
        var request = new PlanRequest(120, List.of(
                goal("A", 10, new SubjectInput("a", null, 2, 0, 0))));
        assertThrows(IllegalArgumentException.class, () -> calculator.calculate(request, TODAY));
    }

    @Test
    void threeCertificationsAreSupportedWithoutOverAllocation() {
        var response = calculator.calculate(new PlanRequest(120, List.of(
                goal("A", 5, sub("a", 2, 1, 0, 0)),
                goal("B", 10, sub("b", 3, 2, 0, 0)),
                goal("C", 15, sub("c", 4, 3, 0, 0)))), TODAY);
        assertEquals(3, response.goals().size());
        assertTrue(response.days().stream().allMatch(day -> day.allocations().stream()
                .mapToInt(Allocation::minutes).sum() <= 120));
    }
    /**
     * 하루 120분에 A·B가 각각 50분대를 쓰면 C 몫은 45분 블록에 못 미치는 자투리만 남는다.
     * 자투리를 버리면 C는 A·B가 끝날 때까지 밀려 마지막에 시간이 모자란다 (총량으로는 충분한 일정인데도).
     */
    @Test
    void threeOverlappingCertificationsAllFinishWhenTotalTimeIsEnough() {
        var response = calculator.calculate(new PlanRequest(120, List.of(
                goal("A", 40, sub("a", 30, 2, 0, 0)),
                goal("B", 40, sub("b", 30, 2, 0, 0)),
                goal("C", 40, sub("c", 12, 2, 0, 0)))), TODAY);
        assertEquals(4320, response.totalRemainingMinutes());   // 40일 × 120분 = 4800분 안에 들어간다
        assertTrue(response.minimumDailyMinutes() <= 120);
        assertEquals(0, response.totalShortfallMinutes());
        assertTrue(response.feasible());
        assertTrue(response.days().stream().allMatch(d -> d.allocatedMinutes() <= 120));
        // C는 A·B가 끝나기를 기다리지 않고 처음 2주 안에 공부를 시작한다
        assertTrue(response.days().stream().filter(d -> d.date().isBefore(TODAY.plusDays(14)))
                .anyMatch(d -> d.allocations().stream().anyMatch(a -> a.goalKey().equals("C"))));
        // 하루에 같은 자격증·과목이 두 줄로 나뉘지 않고, 마지막 잔여시간이 아니면 45분 이상 블록이다
        java.util.Map<String, Integer> left = new java.util.HashMap<>(
                java.util.Map.of("A", 1800, "B", 1800, "C", 720));
        for (var day : response.days()) {
            assertEquals(day.allocations().size(), day.allocations().stream()
                    .map(a -> a.goalKey() + "|" + a.subjectName()).distinct().count());
            for (var a : day.allocations()) {
                int before = left.get(a.goalKey());
                assertTrue(a.minutes() >= 45 || a.minutes() == before, day.date() + " " + a);
                left.put(a.goalKey(), before - a.minutes());
            }
        }
    }

    @Test
    void perCertificationDailyMinutesCapEachGoal() {
        var request = new PlanRequest(180, List.of(
                new GoalInput("ipe", "정처기", TODAY.plusDays(20),
                        List.of(sub("개발", 30, 2, 0, 0)), TODAY, 120),
                new GoalInput("sql", "SQLD", TODAY.plusDays(20),
                        List.of(sub("SQL", 15, 2, 0, 0)), TODAY, 60)));
        var response = calculator.calculate(request, TODAY);
        assertTrue(response.feasible());
        assertEquals(120, response.goals().get(0).dailyMinutes());
        for (var day : response.days()) {
            int ipe = day.allocations().stream().filter(a -> a.goalKey().equals("ipe"))
                    .mapToInt(Allocation::minutes).sum();
            int sql = day.allocations().stream().filter(a -> a.goalKey().equals("sql"))
                    .mapToInt(Allocation::minutes).sum();
            assertTrue(ipe <= 120, day.date() + " 정처기 " + ipe);
            assertTrue(sql <= 60, day.date() + " SQLD " + sql);
        }
        // 상한이 필요량보다 작으면 남는 학습량과 필요한 최소 시간을 알린다.
        var tight = calculator.calculate(new PlanRequest(180, List.of(
                new GoalInput("sql", "SQLD", TODAY.plusDays(10),
                        List.of(sub("SQL", 15, 2, 0, 0)), TODAY, 60))), TODAY);
        assertFalse(tight.feasible());
        assertEquals(900 - 600, tight.totalShortfallMinutes());
        assertTrue(tight.notices().stream().anyMatch(n -> n.contains("최소 하루 90분")));
        assertThrows(IllegalArgumentException.class, () -> calculator.calculate(new PlanRequest(180, List.of(
                new GoalInput("sql", "SQLD", TODAY.plusDays(10),
                        List.of(sub("SQL", 15, 2, 0, 0)), TODAY, 10))), TODAY));
    }

    @Test
    void eachCertificationMayStartOnDifferentDates() {
        var response = calculator.calculate(new PlanRequest(180, List.of(
                new GoalInput("ipe", "정처기", TODAY.plusDays(80),
                        List.of(sub("개발", 9, 2, 0, 0)), TODAY),
                new GoalInput("sql", "SQLD", TODAY.plusDays(85),
                        List.of(sub("SQL", 9, 2, 0, 0)), TODAY.plusDays(25)))), TODAY);
        assertEquals(0, response.totalShortfallMinutes());
        assertEquals(TODAY.plusDays(25), response.goals().get(1).startDate());
        assertTrue(response.days().stream().filter(d -> d.date().isBefore(TODAY.plusDays(25)))
                .allMatch(d -> d.allocations().stream().noneMatch(a -> a.goalKey().equals("sql"))));
        assertTrue(response.days().stream().anyMatch(d -> d.date().equals(TODAY)
                && d.allocations().stream().anyMatch(a -> a.goalKey().equals("ipe"))));
    }

    @Test
    void spreadStudyTimeInsteadOfExhaustingItImmediately() {
        var response = calculator.calculate(new PlanRequest(200, List.of(
                new GoalInput("ipe", "정처기", TODAY.plusDays(115),
                        List.of(sub("개발", 20, 2, 0, 0)), TODAY),
                new GoalInput("sqld", "SQLD", TODAY.plusDays(120),
                        List.of(sub("SQL", 16, 2, 0, 0)), TODAY))), TODAY);
        assertEquals(0, response.totalShortfallMinutes());
        assertTrue(response.days().get(response.days().size()-1).date().isAfter(TODAY.plusDays(85)));
        assertTrue(response.days().stream().allMatch(d -> d.allocatedMinutes() <= 200));
        assertTrue(response.days().stream().allMatch(d -> {
            java.util.Map<String, Integer> perGoal = new java.util.HashMap<>();
            d.allocations().forEach(a -> perGoal.merge(a.goalKey(), a.minutes(), Integer::sum));
            return perGoal.values().stream().allMatch(minutes -> minutes >= 45);
        }));
    }

    @Test
    void invalidGoalStartDateIsRejected() {
        var bad = new PlanRequest(120, List.of(
                new GoalInput("sqld", "SQLD", TODAY.plusDays(10),
                        List.of(sub("SQL", 4, 2, 0, 0)), TODAY.plusDays(11))));
        assertThrows(IllegalArgumentException.class, () -> calculator.calculate(bad, TODAY));
    }

    @Test
    void thirtyMinuteDailyCapacityCanStillAllocateStudy() {
        var response = calculator.calculate(new PlanRequest(30, List.of(
                new GoalInput("sqld", "SQLD", TODAY.plusDays(14),
                        List.of(sub("SQL", 3, 2, 0, 0)), TODAY))), TODAY);
        assertEquals(0, response.totalShortfallMinutes());
        assertTrue(response.days().stream().allMatch(d -> d.allocatedMinutes() <= 30));
    }

    @Test
    void onlyChosenWeekdaysReceiveAllocations() {
        var response = calculator.calculate(new PlanRequest(180, List.of(
                goal("A", 30, sub("개발", 12, 2, 0, 0)),
                goal("B", 30, sub("SQL", 8, 2, 0, 0))), List.of(1,3,5)), TODAY);
        assertEquals(0, response.totalShortfallMinutes());
        assertTrue(response.days().stream().allMatch(day ->
                List.of(1,3,5).contains(day.date().getDayOfWeek().getValue())));
        assertTrue(response.days().stream().allMatch(day -> day.allocatedMinutes() <= 180));
        assertTrue(response.days().stream().anyMatch(day -> day.date().getDayOfWeek().getValue() == 1));
    }

    @Test
    void delayedStartSkipsUnselectedDatesAndRespectsIndependentGoals() {
        var response = calculator.calculate(new PlanRequest(180, List.of(
                new GoalInput("A", "정처기", TODAY.plusDays(30),
                        List.of(sub("개발", 3, 2, 0, 0)), TODAY),
                new GoalInput("B", "SQLD", TODAY.plusDays(35),
                        List.of(sub("SQL", 3, 2, 0, 0)), TODAY.plusDays(10))),
                List.of(2,4)), TODAY);
        assertEquals(0, response.totalShortfallMinutes());
        assertTrue(response.days().stream().allMatch(day -> List.of(2,4)
                .contains(day.date().getDayOfWeek().getValue())));
        assertTrue(response.days().stream().filter(day -> day.date().isBefore(TODAY.plusDays(10)))
                .allMatch(day -> day.allocations().stream().noneMatch(a -> a.goalKey().equals("B"))));
    }

    @Test
    void oneSelectedDayAndNearDeadlineReportsShortfall() {
        var response = calculator.calculate(new PlanRequest(30, List.of(
                goal("A", 6, sub("개발", 10, 2, 0, 0))), List.of(1)), TODAY);
        assertFalse(response.feasible());
        assertTrue(response.totalShortfallMinutes() > 0);
        assertTrue(response.days().stream().allMatch(d -> d.date().getDayOfWeek().getValue() == 1));
    }

    @Test
    void rejectNoWeekdaysAndInvalidDayNumbers() {
        assertThrows(IllegalArgumentException.class, () -> calculator.calculate(
                new PlanRequest(120, List.of(goal("A", 10, sub("개발", 1, 2, 0, 0))), List.of()), TODAY));
        assertThrows(IllegalArgumentException.class, () -> calculator.calculate(
                new PlanRequest(120, List.of(goal("A", 10, sub("개발", 1, 2, 0, 0))), List.of(0,8)), TODAY));
    }

    @Test
    void oldRequestWithoutWeekdaySelectionStillUsesEveryDay() {
        var response = calculator.calculate(new PlanRequest(120, List.of(
                goal("A", 3, sub("개발", 4, 2, 0, 0)))), TODAY);
        assertTrue(response.days().stream().anyMatch(d -> d.date().equals(TODAY)));
        assertEquals(0, response.totalShortfallMinutes());
    }

}
