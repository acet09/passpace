package com.passpace.service;

import java.util.ArrayList;
import java.util.List;

/**
 * [용성] 참고 학습시간 계산 규칙 (DB 없이 테스트 가능한 순수 함수)
 *
 * 합격 후기에는 "총 공부시간"은 자주 있지만 "과목별 시간"은 거의 없다.
 * 그래서 과목별 시간 = 실측 총시간 × (잠정 과목 시간 / 잠정 과목 시간 합) 으로 나눈다.
 * 잠정 과목 시간이 없으면 과목 수로 똑같이 나눈다.
 */
public final class ReferenceMath {

    private ReferenceMath() {
    }

    /**
     * @param total            나눌 총시간
     * @param provisionalHours 과목별 잠정 시간 (순서 = 과목 순서, 값이 없으면 null)
     * @return 과목별 시간 (소수 둘째 자리 반올림)
     */
    public static List<Double> splitByRatio(double total, List<Double> provisionalHours) {
        int n = provisionalHours.size();
        List<Double> out = new ArrayList<>(n);
        if (n == 0) {
            return out;
        }
        double sum = 0;
        boolean allKnown = true;
        for (Double h : provisionalHours) {
            if (h == null || h <= 0) {
                allKnown = false;
            } else {
                sum += h;
            }
        }
        for (Double h : provisionalHours) {
            double share = (allKnown && sum > 0) ? h / sum : 1.0 / n;
            out.add(round2(total * share));
        }
        return out;
    }

    /** 후기 한 건의 총 공부시간: total_hours 가 있으면 그 값, 없으면 준비일수 × 하루 분 / 60 (둘 다 없으면 null) */
    public static Double reviewHours(Double totalHours, Integer prepDays, Integer dailyMinutes) {
        if (totalHours != null && totalHours > 0) {
            return totalHours;
        }
        if (prepDays != null && prepDays > 0 && dailyMinutes != null && dailyMinutes > 0) {
            return round2(prepDays * dailyMinutes / 60.0);
        }
        return null;
    }

    /** STUDY_REFERENCE_STATS.stat_key 형식: 자격증:시험구분:과목(ALL):전공(ALL) */
    public static String statKey(long certId, String examType, Long subjectId, String major) {
        return certId + ":" + examType + ":" + (subjectId == null ? "ALL" : subjectId) + ":" + (major == null ? "ALL" : major);
    }

    public static double round2(double v) {
        return Math.round(v * 100.0) / 100.0;
    }
}
