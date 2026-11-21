package com.passpace.service;

import com.passpace.service.MultiGoalPlanCalculator.GoalInput;
import com.passpace.service.MultiGoalPlanCalculator.PlanRequest;
import com.passpace.service.MultiGoalPlanCalculator.SubjectInput;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [동건] 계획이 밀렸는지 판단하고, 남은 공부량으로 일정을 다시 짤 요청을 만든다 (순수 계산, DB 없음).
 *
 * 밀림 기준: 어제까지 배정된 시간 중 하지 못한 시간이 계획 전체 시간의 20% 이상.
 *   예) 전체 100일치 계획이면 20일치만큼 못 했을 때 재편성을 추천한다.
 * 재편성: 과목마다 (계획한 시간 − 그 과목 할 일에 연결해 기록한 시간)을 남은 양으로 보고,
 *   오늘부터 원래 끝나던 날까지 같은 요일·같은 하루 시간으로 다시 나눈다.
 */
public final class PlanReplanner {

    /** 밀린 시간이 계획 전체의 이 비율(%) 이상이면 재편성을 추천한다. */
    public static final int THRESHOLD_PERCENT = 20;

    /** 저장된 계획의 할 일 한 줄 */
    public record PlannedTask(LocalDate date, String certificationName, String subjectName, Long subjectId,
                              int minutes) {
    }

    /** 얼마나 밀렸는가. needed 가 true 면 재편성을 추천할 때다. */
    public record Status(boolean needed, int totalMinutes, int dueMinutes, int doneMinutes, int behindMinutes,
                         int behindPercent, int thresholdPercent) {
    }

    private PlanReplanner() {
    }

    /**
     * @param doneMinutes 계획 시작일부터 어제까지 기록한 공부 시간(분). 할 일에 연결하지 않은 기록도 포함한다.
     */
    public static Status status(List<PlannedTask> tasks, int doneMinutes, LocalDate today) {
        int total = 0, due = 0;
        LocalDate last = null;
        for (PlannedTask t : tasks) {
            total += t.minutes();
            if (t.date().isBefore(today)) due += t.minutes();
            if (last == null || t.date().isAfter(last)) last = t.date();
        }
        int behind = Math.max(0, due - Math.max(0, doneMinutes));
        int percent = total == 0 ? 0 : (int) Math.floor(behind * 100.0 / total);
        // 계획 기간이 끝났으면 다시 나눌 날짜가 없으므로 추천하지 않는다.
        boolean needed = total > 0 && last != null && !last.isBefore(today)
                && behind * 100L >= (long) THRESHOLD_PERCENT * total;
        return new Status(needed, total, due, Math.max(0, doneMinutes), behind, percent, THRESHOLD_PERCENT);
    }

    /** 계산기에서 목표를 구분하는 키 (자격증 이름마다 하나) */
    public static String goalKey(String certificationName) {
        return "replan|" + certificationName;
    }

    /**
     * 남은 공부량을 오늘부터 다시 나누는 계획 요청.
     *
     * @param doneBySubject "자격증|과목" → 그 과목 할 일에 연결해 기록한 시간(분)
     * @param dayCaps       요일(1=월 … 7=일) → 그날 쓸 수 있는 시간(분)
     * @return 다시 나눌 것이 없으면 null
     */
    public static PlanRequest request(List<PlannedTask> tasks, Map<String, Integer> doneBySubject,
                                      Map<Integer, Integer> dayCaps, LocalDate today) {
        // 자격증 → 과목 → 계획한 시간, 그리고 자격증별 마지막 공부일
        Map<String, Map<String, Integer>> planned = new LinkedHashMap<>();
        Map<String, LocalDate> lastDay = new LinkedHashMap<>();
        for (PlannedTask t : tasks) {
            planned.computeIfAbsent(t.certificationName(), k -> new LinkedHashMap<>())
                    .merge(t.subjectName(), t.minutes(), Integer::sum);
            lastDay.merge(t.certificationName(), t.date(), (a, b) -> a.isAfter(b) ? a : b);
        }
        List<GoalInput> goals = new ArrayList<>();
        for (Map.Entry<String, Map<String, Integer>> cert : planned.entrySet()) {
            // 원래 계획의 마지막 공부일 다음 날을 끝낼 날짜로 본다 → 새 일정이 원래 기간을 넘지 않는다.
            LocalDate end = lastDay.get(cert.getKey()).plusDays(1);
            if (!end.isAfter(today)) continue;   // 이미 기간이 끝난 자격증
            List<SubjectInput> subjects = new ArrayList<>();
            for (Map.Entry<String, Integer> subject : cert.getValue().entrySet()) {
                int done = doneBySubject.getOrDefault(cert.getKey() + "|" + subject.getKey(), 0);
                int remaining = subject.getValue() - Math.max(0, done);
                if (remaining <= 0) continue;
                // 이해도 2(가중치 1.0)로 넣어 남은 분을 그대로 배정한다.
                subjects.add(new SubjectInput(subject.getKey(), remaining / 60.0, 2, 0, 0));
            }
            if (!subjects.isEmpty())
                goals.add(new GoalInput(goalKey(cert.getKey()), cert.getKey(), end, List.copyOf(subjects), today));
        }
        if (goals.isEmpty() || dayCaps == null || dayCaps.isEmpty()) return null;
        return new PlanRequest(null, List.copyOf(goals), null, new TreeMap<>(dayCaps));
    }

    private static final Pattern DAY_ENTRY = Pattern.compile("\"([1-7])\"\\s*:\\s*(\\d{1,3})");
    private static final Pattern DAILY_IN_NAME = Pattern.compile("하루 (\\d{2,3})분");

    /**
     * 저장된 계획에서 요일별 가능시간을 알아낸다.
     *  1) weekday_minutes 칸({"1":60,"6":240})이 있으면 그 값
     *  2) 없으면(예전에 저장한 계획): 공부가 배정된 요일 + 계획 이름의 "하루 N분", 그것도 없으면 하루 최대 배정 시간
     */
    public static Map<Integer, Integer> dayCaps(String weekdayMinutesJson, String planName, List<PlannedTask> tasks) {
        Map<Integer, Integer> caps = new TreeMap<>();
        if (weekdayMinutesJson != null) {
            Matcher m = DAY_ENTRY.matcher(weekdayMinutesJson);
            while (m.find()) {
                int minutes = Integer.parseInt(m.group(2));
                if (minutes >= 30 && minutes <= 960) caps.put(Integer.parseInt(m.group(1)), minutes);
            }
            if (!caps.isEmpty()) return caps;
        }
        Map<LocalDate, Integer> perDay = new LinkedHashMap<>();
        for (PlannedTask t : tasks) perDay.merge(t.date(), t.minutes(), Integer::sum);
        int daily = perDay.values().stream().mapToInt(Integer::intValue).max().orElse(0);
        Matcher named = DAILY_IN_NAME.matcher(planName == null ? "" : planName);
        if (named.find()) daily = Math.max(daily, Integer.parseInt(named.group(1)));
        daily = Math.max(30, Math.min(960, daily));
        for (LocalDate date : perDay.keySet()) caps.put(date.getDayOfWeek().getValue(), daily);
        return caps;
    }
}
