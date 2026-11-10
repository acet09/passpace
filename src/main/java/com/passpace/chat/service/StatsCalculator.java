package com.passpace.chat.service;

import com.passpace.chat.dto.ChatDtos.Evidence;
import com.passpace.chat.dto.ChatDtos.StatsSummary;
import com.passpace.common.stats.ReviewSample;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * [동건] 처리 ③ 후기 목록 → 통계 (Spring 없이 테스트 가능한 순수 클래스)
 * 평균·중앙값 같은 숫자는 반드시 여기서 계산한다. LLM 에게 계산을 맡기지 않는다.
 */
public class StatsCalculator {

    private static final int EVIDENCE_LIMIT = 4;

    /**
     * @param samples       조건에 맞는 후기 (합격·불합격 모두)
     * @param remainingDays 사용자의 남은 일수 (근거 후기를 고를 때 가까운 순)
     * @param minSample     통계 사용 최소 표본 (기획안: 10건)
     */
    public StatsSummary summarize(List<ReviewSample> samples, int remainingDays, String conditionLabel, int minSample) {
        List<ReviewSample> all = samples == null ? List.of() : samples;
        List<ReviewSample> passed = all.stream().filter(r -> Boolean.TRUE.equals(r.passed())).toList();
        List<ReviewSample> failed = all.stream().filter(r -> Boolean.FALSE.equals(r.passed())).toList();
        List<Integer> daily = passed.stream().map(ReviewSample::dailyMinutes).filter(Objects::nonNull).sorted().toList();
        List<Integer> failDaily = failed.stream().map(ReviewSample::dailyMinutes).filter(Objects::nonNull).toList();
        List<Double> totalHours = passed.stream().map(ReviewSample::totalHours).filter(Objects::nonNull)
                .map(java.math.BigDecimal::doubleValue).toList();
        List<Integer> prep = passed.stream().map(ReviewSample::prepDays).filter(Objects::nonNull).toList();
        Map<String, Integer> methods = new HashMap<>();
        passed.stream().map(ReviewSample::studyMethod).filter(Objects::nonNull)
                .forEach(m -> methods.merge(m, 1, Integer::sum));
        String top = methods.entrySet().stream()
                .sorted(Comparator.<Map.Entry<String, Integer>>comparingInt(Map.Entry::getValue).reversed()
                        .thenComparing(Map.Entry::getKey))
                .map(Map.Entry::getKey).findFirst().orElse(null);
        int topCount = top == null ? 0 : methods.get(top);
        List<ReviewSample> evidenceSamples = passed.stream()
                .filter(r -> r.evidenceText() != null && !r.evidenceText().isBlank())
                .sorted(Comparator.comparingInt(r -> r.prepDays() == null ? Integer.MAX_VALUE
                        : Math.abs(r.prepDays() - remainingDays)))
                .limit(EVIDENCE_LIMIT).toList();
        List<Evidence> evidences = new ArrayList<>();
        for (ReviewSample r : evidenceSamples) evidences.add(new Evidence(evidences.size() + 1,
                r.evidenceText(), r.sourceUrl(), r.prepDays(), r.dailyMinutes()));
        return new StatsSummary(daily.size() >= minSample, conditionLabel, daily.size(), all.size(),
                passed.size(), failed.size(), avg(daily), median(daily),
                daily.isEmpty() ? null : daily.getFirst(), daily.isEmpty() ? null : daily.getLast(),
                totalHours.isEmpty() ? null : (int) Math.round(totalHours.stream().mapToDouble(Double::doubleValue).average().orElse(0)),
                avg(prep), top, topCount, avg(failDaily), evidences);
    }

    static Integer avg(List<Integer> values) {
        if (values == null || values.isEmpty()) return null;
        return (int) Math.round(values.stream().mapToLong(Integer::longValue).average().orElse(0));
    }

    /** values 는 정렬된 상태여야 한다 */
    static Integer median(List<Integer> sorted) {
        if (sorted == null || sorted.isEmpty()) return null;
        int n = sorted.size();
        return n % 2 == 1 ? sorted.get(n / 2)
                : (int) Math.round((sorted.get(n / 2 - 1) + sorted.get(n / 2)) / 2.0);
    }
}
