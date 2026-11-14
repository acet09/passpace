package com.passpace.service;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.HashSet;

/**
 * [동건] 독립 목표 시험일 + 공유 하루 학습시간을 사용한 다중 자격증 계획 미리보기.
 * 순수 Java 계산 엔진. 다른 팀원 소유의 스키마, DTO, 서비스 계약을 변경하지 않는다.
 * 실제 평균 학습시간은 입력으로 주어져야 한다. 없는 값을 임의로 추정하지 않는다.
 */
public class MultiGoalPlanCalculator {

    public record SubjectInput(String name, Double baseHours, Integer familiarity,
                               Integer progressPercent, Integer actualMinutes) {}
    public record GoalInput(String key, String certificationName, LocalDate examDate,
                            List<SubjectInput> subjects, LocalDate startDate) {
        // 이전 4개 인자 생성 방식 유지: 시작일을 지정하지 않으면 계획 생성일을 사용한다.
        public GoalInput(String key, String certificationName, LocalDate examDate,
                         List<SubjectInput> subjects) {
            this(key, certificationName, examDate, subjects, null);
        }
    }
    /** 요일 1=월요일, 2=화요일, ... 7=일요일. null은 기존 API 호환을 위해 매일로 처리한다. */
    public record PlanRequest(Integer dailyMinutes, List<GoalInput> goals, List<Integer> studyWeekdays) {
        public PlanRequest(Integer dailyMinutes, List<GoalInput> goals) {
            this(dailyMinutes, goals, null);
        }
    }
    public record SubjectSummary(String name, int familiarity, double weight,
                                 double baseHours, int progressPercent, int actualMinutes,
                                 double observedSpeedFactor, int remainingMinutes) {}
    public record GoalSummary(String key, String certificationName, LocalDate examDate,
                              LocalDate startDate, int remainingDays, int remainingMinutes, int scheduledMinutes,
                              int shortfallMinutes, LocalDate projectedCompletionDate,
                              List<SubjectSummary> subjects) {}
    public record Allocation(String goalKey, String certificationName,
                             String subjectName, int minutes) {}
    public record DaySchedule(LocalDate date, int availableMinutes, int allocatedMinutes,
                              List<Allocation> allocations) {}
    public record Feasibility(LocalDate deadline, int requiredMinutes, int availableMinutes,
                              int shortageMinutes) {}
    public record PlanResponse(LocalDate calculatedOn, int dailyMinutes,
                               int totalRemainingMinutes, int totalShortfallMinutes,
                               int minimumDailyMinutes, int additionalDailyMinutes, boolean feasible, List<GoalSummary> goals,
                               List<Feasibility> deadlineChecks,
                               List<DaySchedule> days, List<String> notices) {}

    private static final int MAX_HORIZON_DAYS = 540;
    // 과목을 8분씩 찢어 배정하는 일을 막기 위한 목표당 1회 학습 블록.
    // 단, 목표에 남은 전체 학습량이 이보다 작을 때는 마지막 잔여시간을 허용한다.
    private static final int MIN_SESSION_MINUTES = 45;
    // 시험 직전 1주일은 재점검/복습을 위한 여유로 남긴다(해당 시간은 임의 생성하지 않음).
    private static final int MAX_BUFFER_DAYS = 7;
    private static final double MAX_BASE_HOURS = 2000;
    private static final int MAX_GOALS = 12;
    private static final int MAX_SUBJECTS = 35;

    /** today는 테스트할 수 있도록 인자로 전달한다. 시험 당일은 학습일에서 제외한다. */
    public PlanResponse calculate(PlanRequest request, LocalDate today) {
        Objects.requireNonNull(today, "오늘 날짜가 필요합니다.");
        if (request == null || request.dailyMinutes() == null ||
                request.dailyMinutes() < 30 || request.dailyMinutes() > 960)
            throw new IllegalArgumentException("하루 총 공부시간은 30~960분으로 입력해 주세요.");
        if (request.goals() == null || request.goals().isEmpty() || request.goals().size() > MAX_GOALS)
            throw new IllegalArgumentException("자격증 목표는 1~12개 선택해 주세요.");

        Set<Integer> allowedWeekdays = normalizeWeekdays(request.studyWeekdays());
        Set<String> keys = new HashSet<>();
        List<GoalWork> goals = new ArrayList<>();
        int allMinutes = 0;
        for (GoalInput goal : request.goals()) {
            if (goal == null || !safeName(goal.key(), 100) || !safeName(goal.certificationName(), 150)
                    || !keys.add(goal.key()))
                throw new IllegalArgumentException("목표 이름이 비어 있거나 중복되었습니다.");
            if (goal.examDate() == null || !goal.examDate().isAfter(today)
                    || ChronoUnit.DAYS.between(today, goal.examDate()) > MAX_HORIZON_DAYS)
                throw new IllegalArgumentException(goal.certificationName() + ": 시험일은 내일부터 540일 이내로 지정해 주세요.");
            LocalDate start = goal.startDate() == null ? today : goal.startDate();
            LocalDate effectiveStart = start.isBefore(today) ? today : start;
            if (!start.isBefore(goal.examDate()) || effectiveStart.isBefore(today)
                    || ChronoUnit.DAYS.between(today, start) > MAX_HORIZON_DAYS)
                throw new IllegalArgumentException(goal.certificationName()
                        + ": 학습 시작일은 시험일보다 이전이어야 합니다.");
            if (goal.subjects() == null || goal.subjects().isEmpty() || goal.subjects().size() > MAX_SUBJECTS)
                throw new IllegalArgumentException(goal.certificationName() + ": 과목을 1~35개 입력해 주세요.");
            List<SubjectWork> subjects = new ArrayList<>();
            Set<String> names = new HashSet<>();
            int goalMinutes = 0;
            for (SubjectInput subject : goal.subjects()) {
                if (subject == null || !safeName(subject.name(), 150) || !names.add(subject.name()))
                    throw new IllegalArgumentException(goal.certificationName() + ": 과목 이름이 비어 있거나 중복되었습니다.");
                if (subject.baseHours() == null || !Double.isFinite(subject.baseHours())
                        || subject.baseHours() <= 0 || subject.baseHours() > MAX_BASE_HOURS)
                    throw new IllegalArgumentException(goal.certificationName() + " / " + subject.name()
                            + ": 검증 가능한 기준시간 또는 명시적인 테스트용 시간을 입력해 주세요.");
                if (subject.familiarity() == null || subject.familiarity() < 1 || subject.familiarity() > 3)
                    throw new IllegalArgumentException(subject.name() + ": 사전 이해도를 직접 선택해 주세요.");
                int progress = subject.progressPercent() == null ? 0 : subject.progressPercent();
                int actual = subject.actualMinutes() == null ? 0 : subject.actualMinutes();
                if (progress < 0 || progress > 100 || actual < 0 || actual > 200_000)
                    throw new IllegalArgumentException(subject.name() + ": 진도율 또는 실제 학습시간이 올바르지 않습니다.");

                double weight = switch (subject.familiarity()) {
                    case 1 -> 1.3;
                    case 2 -> 1.0;
                    default -> 0.7;
                };
                double expectedTotal = subject.baseHours() * 60 * weight;
                double speedFactor = 1.0;
                if (progress > 0 && actual > 0) {
                    double observed = actual / (expectedTotal * progress / 100.0);
                    // 극단적인 초반 진도율은 그대로 외삽하지 않는다. 관측 50%만 반영.
                    speedFactor = Math.max(0.65, Math.min(1.75, (1 + observed) / 2));
                }
                int remaining = (int) Math.ceil(expectedTotal * (100 - progress) / 100.0 * speedFactor);
                if (remaining < 0) remaining = 0;
                goalMinutes = Math.addExact(goalMinutes, remaining);
                subjects.add(new SubjectWork(subject, weight, speedFactor, remaining));
            }
            allMinutes = Math.addExact(allMinutes, goalMinutes);
            // 입문 과목을 먼저 배치하되 각 과목의 필요시간은 입력된 이해도 가중치로 별도 계산
            subjects.sort(Comparator.comparingInt(s -> s.input.familiarity()));
            int studyWindowDays = (int) ChronoUnit.DAYS.between(effectiveStart, goal.examDate());
            // 긴 구간에서만 최대 7일의 시험 전 여유를 둔다. 시작일을 지정한 목표만 그 이후에 시작한다.
            int bufferDays = studyWindowDays >= 14 ? Math.min(MAX_BUFFER_DAYS, studyWindowDays / 10) : 0;
            LocalDate pacedEnd = goal.examDate().minusDays(bufferDays + 1);
            // 시험 전 여유기간 때문에 실제 선택한 학습 요일이 모두 없어질 경우,
            // 최소한 시험 전날까지는 계획할 수 있게 완화한다.
            if (countStudyDays(effectiveStart, pacedEnd.plusDays(1), allowedWeekdays) == 0)
                pacedEnd = goal.examDate().minusDays(1);
            GoalWork workingGoal = new GoalWork(goal, subjects, goalMinutes,
                    start, effectiveStart, pacedEnd);
            if (goalMinutes == 0) workingGoal.finishedOn = today;
            goals.add(workingGoal);
        }
        goals.sort(Comparator.comparing(g -> g.input.examDate()));
        List<Feasibility> checks = new ArrayList<>();
        int cumulative = 0;
        int minimumDailyMinutes = 0;
        // 누적 마감량은 응답 호환성을 위해 유지한다. 별도로 각 시작/마감 구간의 수요 밀도를 확인한다.
        for (GoalWork g : goals) {
            cumulative = Math.addExact(cumulative, g.originalMinutes);
            int daysUntil = countStudyDays(today, g.input.examDate(), allowedWeekdays);
            int available = daysUntil * request.dailyMinutes();
            // 이전 응답 스키마의 마감일까지 누적 총량 점검은 유지한다.
            checks.add(new Feasibility(g.input.examDate(), cumulative, available,
                    Math.max(0, cumulative - available)));
        }
        // 두 자격증의 시험일이 겹치는 경우 한 자격증의 시간만 계산하는 오류 방지.
        // [A,B) 구간에 반드시 포함돼야 하는 목표의 수요 / 해당 구간의 날짜 수.
        boolean hasNoAvailableWindow = false;
        for (GoalWork first : goals) {
            for (GoalWork last : goals) {
                LocalDate a = first.effectiveStart;
                LocalDate b = last.input.examDate();
                if (!b.isAfter(a)) continue;
                int duration = countStudyDays(a, b, allowedWeekdays);
                int demand = 0;
                for (GoalWork g : goals) {
                    if (!g.effectiveStart.isBefore(a) && !g.input.examDate().isAfter(b))
                        demand = Math.addExact(demand, g.originalMinutes);
                }
                if (duration == 0) {
                    if (demand > 0) hasNoAvailableWindow = true;
                    continue;
                }
                minimumDailyMinutes = Math.max(minimumDailyMinutes,
                        (demand + duration - 1) / duration);
            }
        }

        List<DaySchedule> days = new ArrayList<>();
        LocalDate latest = goals.get(goals.size() - 1).input.examDate();
        for (LocalDate day = today; day.isBefore(latest); day = day.plusDays(1)) {
            if (!allowedWeekdays.contains(day.getDayOfWeek().getValue())) continue;
            final LocalDate scheduledDay = day;
            List<GoalWork> active = goals.stream()
                    .filter(g -> g.remaining > 0 && !scheduledDay.isBefore(g.effectiveStart)
                            && scheduledDay.isBefore(g.input.examDate()))
                    .toList();
            if (active.isEmpty()) continue;
            int capacity = request.dailyMinutes();
            int sessionMin = Math.min(MIN_SESSION_MINUTES, request.dailyMinutes());
            Map<GoalWork, Integer> budgets = new LinkedHashMap<>();
            // 기본 예상학습량을 목표별 [학습 시작일, 시험 직전] 구간에 분산한다.
            // 하루 가능시간은 '매일 무조건 채우는 의무량'이 아니라 상한이다.
            for (GoalWork g : active) {
                int pacedDays = countStudyDays(g.effectiveStart, g.pacedEnd.plusDays(1), allowedWeekdays);
                int elapsed = countStudyDays(g.effectiveStart, day.plusDays(1), allowedWeekdays);
                int targetDone = pacedDays == 0 ? g.originalMinutes :
                        (int) Math.ceil(g.originalMinutes * (double) Math.min(elapsed, pacedDays) / pacedDays);
                int due = Math.max(0, targetDone - g.scheduled);
                // 날짜가 임박한 경우 이전에 못 채운 양을 우선 배정한다.
                int daysLeft = countStudyDays(day, g.input.examDate(), allowedWeekdays);
                int rescue = (g.remaining + daysLeft - 1) / daysLeft;
                int demand = Math.max(due, rescue);
                // 선택한 시작일이 실제 첫 학습일이 되도록 첫날에는 한 블록을 잡는다.
                if (day.equals(nextStudyDay(g.effectiveStart, allowedWeekdays)))
                    demand = Math.max(demand, sessionMin);
                if (demand < sessionMin && day.isBefore(g.pacedEnd)) {
                    budgets.put(g, 0);
                    continue;
                }
                int wanted = Math.max(sessionMin, demand);
                // 끝부분이 작은 경우 같은 날의 학습 블록에 합쳐 처리한다.
                if (g.remaining > wanted && g.remaining - wanted < sessionMin)
                    wanted = g.remaining;
                budgets.put(g, Math.min(g.remaining, wanted));
            }
            // 마감이 가까운 자격증을 우선하되 다른 자격증에 8분 같은 짧은 몫을 강제하지 않는다.
            List<Allocation> allocations = new ArrayList<>();
            int allocated = 0;
            for (GoalWork g : active) {
                if (capacity == 0) break;
                int wanted = budgets.getOrDefault(g, 0);
                if (wanted == 0) continue;
                if (capacity < sessionMin && g.remaining >= sessionMin) continue;
                int grant = Math.min(wanted, capacity);
                if (grant < sessionMin && g.remaining >= sessionMin) continue;
                // 남은 목표가 매우 작을 때만 최소 블록 미만의 '마지막 마무리' 배정을 허용한다.
                if (grant < sessionMin && grant != g.remaining) continue;
                int budget = grant;
                for (SubjectWork subject : g.subjects) {
                    if (budget <= 0) break;
                    if (subject.remaining == 0) continue;
                    int minutes = Math.min(budget, subject.remaining);
                    subject.remaining -= minutes;
                    g.remaining -= minutes;
                    g.scheduled += minutes;
                    budget -= minutes;
                    allocated += minutes;
                    allocations.add(new Allocation(g.input.key(), g.input.certificationName(),
                            subject.input.name(), minutes));
                }
                capacity -= grant - budget;
                if (g.remaining == 0 && g.finishedOn == null) g.finishedOn = day;
            }
            if (allocated > 0) days.add(new DaySchedule(day, request.dailyMinutes(),
                    allocated, List.copyOf(allocations)));
        }

        int shortage = goals.stream().mapToInt(g -> g.remaining).sum();
        List<GoalSummary> summaries = new ArrayList<>();
        for (GoalWork g : goals) {
            List<SubjectSummary> subs = new ArrayList<>();
            for (SubjectWork s : g.subjects) {
                subs.add(new SubjectSummary(s.input.name(), s.input.familiarity(), s.weight,
                        s.input.baseHours(), s.input.progressPercent() == null ? 0 : s.input.progressPercent(),
                        s.input.actualMinutes() == null ? 0 : s.input.actualMinutes(),
                        round(s.speedFactor), s.originalMinutes));
            }
            summaries.add(new GoalSummary(g.input.key(), g.input.certificationName(),
                    g.input.examDate(), g.startDate,
                    (int) ChronoUnit.DAYS.between(today, g.input.examDate()),
                    g.originalMinutes, g.scheduled, g.remaining, g.finishedOn, List.copyOf(subs)));
        }
        List<String> notices = new ArrayList<>();
        notices.add("학습시간은 과목별 입력 기준시간 × 사전 이해도(낮음 1.3 / 보통 1.0 / 높음 0.7)로 계산한 추정치입니다.");
        notices.add("진도와 실제 소요시간이 함께 입력되면 관측 속도를 보수적으로 반영해 남은 시간을 다시 계산합니다.");
        notices.add("각 목표는 독립적인 시작일(기본값 오늘)부터 시험일 전까지 배정하고, 같은 날의 하루 가용시간을 공유합니다.");
        notices.add("공부 요일: " + weekdayLabels(allowedWeekdays) + ". 선택한 요일에만 배정하며, 하루 시간은 두 자격증이 함께 씁니다.");
        notices.add("하루 가용시간은 상한이며 매일 전부 채우지 않습니다. 목표당 기본 학습 블록은 하루 시간이 45분 이상일 때 45분입니다(최종 잔여시간 제외).");
        notices.add("예상 학습량은 임시 기준시간을 활용합니다. 기출·복습/모의고사 추가 시간을 사실인 것처럼 자동 생성하지 않습니다.");
        if (hasNoAvailableWindow)
            notices.add("어떤 목표의 시작일~시험일 사이에 선택한 학습 요일이 없습니다. 요일 또는 시작일·시험일을 조정해 주세요.");
        if (shortage > 0)
            notices.add("선택한 요일·가능시간·시험일로는 일부 학습량이 남습니다. 요일 추가, 하루 시간 증가 또는 목표일 조정이 필요합니다.");
        return new PlanResponse(today, request.dailyMinutes(), allMinutes, shortage,
                minimumDailyMinutes, Math.max(0, minimumDailyMinutes - request.dailyMinutes()),
                shortage == 0, List.copyOf(summaries), List.copyOf(checks),
                List.copyOf(days), List.copyOf(notices));
    }

    private static Set<Integer> normalizeWeekdays(List<Integer> requested) {
        if (requested == null) return Set.of(1, 2, 3, 4, 5, 6, 7); // 기존 요청 호환
        if (requested.isEmpty() || requested.size() > 7)
            throw new IllegalArgumentException("공부할 요일을 월~일 중 최소 한 개 이상 선택해 주세요.");
        Set<Integer> days = new HashSet<>();
        for (Integer day : requested) {
            if (day == null || day < 1 || day > 7 || !days.add(day))
                throw new IllegalArgumentException("요일 값은 중복 없이 월=1부터 일=7까지만 입력해 주세요.");
        }
        return days;
    }

    /** start 포함, endExclusive 제외. 시험 당일은 계산에서 제외한다. */
    private static int countStudyDays(LocalDate start, LocalDate endExclusive, Set<Integer> days) {
        int count = 0;
        for (LocalDate date = start; date.isBefore(endExclusive); date = date.plusDays(1))
            if (days.contains(date.getDayOfWeek().getValue())) count++;
        return count;
    }

    private static LocalDate nextStudyDay(LocalDate start, Set<Integer> days) {
        LocalDate date = start;
        for (int i = 0; i < 7; i++, date = date.plusDays(1))
            if (days.contains(date.getDayOfWeek().getValue())) return date;
        throw new IllegalArgumentException("선택한 학습 요일이 없습니다.");
    }

    private static String weekdayLabels(Set<Integer> days) {
        String[] names = {"월", "화", "수", "목", "금", "토", "일"};
        List<String> chosen = new ArrayList<>();
        for (int i = 1; i <= 7; i++) if (days.contains(i)) chosen.add(names[i - 1]);
        return String.join("·", chosen);
    }

    private static boolean safeName(String s, int max) {
        return s != null && !s.isBlank() && s.length() <= max;
    }
    private static boolean dayIsBefore(LocalDate day, LocalDate deadline) {
        return day.isBefore(deadline);
    }
    private static double round(double v) {
        return Math.round(v * 100.0) / 100.0;
    }
    private static final class SubjectWork {
        final SubjectInput input;
        final double weight;
        final double speedFactor;
        final int originalMinutes;
        int remaining;
        SubjectWork(SubjectInput input, double weight, double speedFactor, int minutes) {
            this.input = input;
            this.weight = weight;
            this.speedFactor = speedFactor;
            this.originalMinutes = minutes;
            this.remaining = minutes;
        }
    }
    private static final class GoalWork {
        final GoalInput input;
        final List<SubjectWork> subjects;
        final int originalMinutes;
        final LocalDate startDate;
        final LocalDate effectiveStart;
        final LocalDate pacedEnd;
        int remaining;
        int scheduled;
        LocalDate finishedOn;
        GoalWork(GoalInput input, List<SubjectWork> subjects, int minutes,
                 LocalDate startDate, LocalDate effectiveStart, LocalDate pacedEnd) {
            this.input = input;
            this.subjects = subjects;
            this.originalMinutes = minutes;
            this.remaining = minutes;
            this.startDate = startDate;
            this.effectiveStart = effectiveStart;
            this.pacedEnd = pacedEnd;
        }
    }
}
