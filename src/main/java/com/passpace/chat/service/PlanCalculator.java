package com.passpace.chat.service;

import com.passpace.chat.dto.ChatDtos.PhasePlan;
import com.passpace.chat.dto.ChatDtos.PlanNumbers;
import com.passpace.chat.dto.ChatDtos.SubjectPlan;
import com.passpace.common.code.StudyMethod;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

/**
 * [동건] 처리 ② Java 계산 (Spring 없이 테스트 가능한 순수 클래스)
 *  - 남은 일수, 주 수, 총 가용시간
 *  - 단계 나누기: 기초·이론 → 기출 반복 → 마무리
 *    비율은 유사 집단 합격자에게 가장 많았던 학습 방식으로 정한다
 *      이론 위주 50/35/15, 병행 40/45/15, 기출 위주 30/55/15 (초기 설계값, 팀에서 조정)
 *    3주 이상 남으면 단계를 주 단위로 끊는다 (주차가 겹치지 않게, 실제 일수는 비율과 조금 다를 수 있음)
 *  - 과목별 배분: 기획안 3.3 이해도 가중치 1단계 1.3 / 2단계 1.0 / 3단계 0.7 (모르면 1.0)
 * LLM 은 이 숫자를 문장으로 풀어 쓰기만 한다.
 */
public class PlanCalculator {

    public PlanNumbers calculate(LocalDate today, LocalDate examDate, int dailyMinutes,
                                 List<String> subjects, Map<String, Integer> familiarity, StudyMethod method) {
        int remaining = (int) Math.max(0, ChronoUnit.DAYS.between(today, examDate));
        int weeks = (remaining + 6) / 7;
        double totalHours = round1(remaining * dailyMinutes / 60.0);
        return new PlanNumbers(remaining, weeks, dailyMinutes, totalHours,
                phases(remaining, dailyMinutes, method),
                subjects(subjects, familiarity == null ? Map.of() : familiarity, totalHours));
    }

    List<PhasePlan> phases(int remaining, int dailyMinutes, StudyMethod method) {
        if (remaining <= 0) return List.of();
        if (remaining < 7) return List.of(new PhasePlan(1, "마무리", dayLabel(1, remaining), 100,
                remaining, round1(remaining * dailyMinutes / 60.0), "핵심 개념·오답 최종 점검"));
        int[] pct = switch (method == null ? StudyMethod.BALANCED : method) {
            case THEORY -> new int[]{50, 35, 15};
            case PAST_EXAM -> new int[]{30, 55, 15};
            case BALANCED -> new int[]{40, 45, 15};
        };
        int d1, d2, d3;
        String r1, r2, r3;
        if (remaining >= 21) {
            int fullWeeks = remaining / 7;
            int w1 = Math.max(1, (int) Math.round(fullWeeks * pct[0] / 100.0));
            int w3 = Math.max(1, (int) Math.round(fullWeeks * pct[2] / 100.0));
            if (w1 + w3 > fullWeeks - 1) w1 = fullWeeks - 1 - w3;
            int w2 = fullWeeks - w1 - w3;
            d1 = w1 * 7;
            d2 = w2 * 7;
            d3 = remaining - d1 - d2;
            r1 = weekLabel(1, w1);
            r2 = weekLabel(w1 + 1, w1 + w2);
            r3 = weekLabel(w1 + w2 + 1, (remaining + 6) / 7);
        } else {
            d1 = Math.max(1, (int) Math.round(remaining * pct[0] / 100.0));
            d3 = Math.max(1, (int) Math.round(remaining * pct[2] / 100.0));
            if (d1 + d3 > remaining - 1) d1 = remaining - 1 - d3;
            d2 = remaining - d1 - d3;
            r1 = dayLabel(1, d1);
            r2 = dayLabel(d1 + 1, d1 + d2);
            r3 = dayLabel(d1 + d2 + 1, remaining);
        }
        return List.of(
                new PhasePlan(1, "기초·이론", r1, pct[0], d1, round1(d1 * dailyMinutes / 60.0), "핵심 개념 정리"),
                new PhasePlan(2, "기출 반복", r2, pct[1], d2, round1(d2 * dailyMinutes / 60.0), "기출 풀이·오답 점검"),
                new PhasePlan(3, "마무리", r3, pct[2], d3, round1(d3 * dailyMinutes / 60.0), "취약 과목 보완·최종 복습"));
    }

    List<SubjectPlan> subjects(List<String> subjects, Map<String, Integer> familiarity, double totalHours) {
        if (subjects == null || subjects.isEmpty()) return List.of();
        Map<String, Integer> known = familiarity == null ? Map.of() : familiarity;
        double sum = subjects.stream().mapToDouble(s -> weight(known.get(s))).sum();
        List<SubjectPlan> result = new ArrayList<>();
        for (String subject : subjects) {
            Integer level = known.get(subject);
            double w = weight(level);
            result.add(new SubjectPlan(subject, level, w, round1(totalHours * w / sum)));
        }
        result.sort(Comparator.comparingDouble(SubjectPlan::weight).reversed()
                .thenComparing(SubjectPlan::subjectName));
        return result;
    }

    private static String weekLabel(int from, int to) {
        return from == to ? from + "주차" : from + "~" + to + "주차";
    }

    static double weight(Integer familiarity) {
        return familiarity == null ? 1.0 : switch (familiarity) {
            case 1 -> 1.3;
            case 2 -> 1.0;
            case 3 -> 0.7;
            default -> 1.0;
        };
    }

    private static String dayLabel(int from, int to) {
        return from == to ? from + "일차" : from + "~" + to + "일차";
    }

    static double round1(double v) {
        return Math.round(v * 10.0) / 10.0;
    }
}
