package com.passpace.service;

import java.util.ArrayList;
import java.util.Collections;
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

    /**
     * [11-16] 중앙값. 소수의 아주 긴 준비기간(300시간 등)에 평균이 끌려가는 것을 막는다.
     * 짝수 개면 가운데 두 값의 평균. 비어 있으면 0.
     */
    public static double median(List<Double> values) {
        if (values == null || values.isEmpty()) {
            return 0;
        }
        List<Double> sorted = new ArrayList<>(values);
        Collections.sort(sorted);
        int n = sorted.size();
        double m = n % 2 == 1 ? sorted.get(n / 2) : (sorted.get(n / 2 - 1) + sorted.get(n / 2)) / 2.0;
        return round2(m);
    }

    /**
     * [11-16] 하루 공부시간이 없는 후기("3일컷", "일주일")를 위한 보충.
     * reviewHours 로 계산이 안 되고 준비일수만 있으면, 같은 자격증·시험 후기들의 하루 공부시간 중앙값(fallbackDailyMinutes)을 곱한다.
     * 보충값이 없으면 null (지금처럼 표본에서 빠진다).
     */
    public static Double reviewHoursWithFallback(Double totalHours, Integer prepDays, Integer dailyMinutes,
                                                 Double fallbackDailyMinutes) {
        Double h = reviewHours(totalHours, prepDays, dailyMinutes);
        if (h != null) {
            return h;
        }
        if (prepDays != null && prepDays > 0 && (dailyMinutes == null || dailyMinutes <= 0)
                && fallbackDailyMinutes != null && fallbackDailyMinutes > 0) {
            return round2(prepDays * fallbackDailyMinutes / 60.0);
        }
        return null;
    }

    /**
     * [11-19] 표본에 추정값(준비일수 × 같은 시험 하루시간 중앙값)을 섞을지는 "전공 전체" 그룹의 직접 값 수로 한 번만 정한다.
     * 전공 전체의 직접 값이 최소 표본 이상이면 어느 전공 그룹에서도 추정값을 섞지 않는다.
     * (그룹마다 따로 정하면 전공 그룹이 추정값으로 채워져 전공 전체보다 표본이 많아지는 문제가 생김)
     */
    public static List<Double> pickHours(List<Double> direct, List<Double> guessed, int allMajorDirectCount, int minSample) {
        List<Double> hours = new ArrayList<>(direct);
        if (allMajorDirectCount < minSample) {
            hours.addAll(guessed);
        }
        return hours;
    }

    /** [11-21] 표본 구성 결과: 쓸 값들, 그중 네이버 보충 건수, 추정값 건수 */
    public record Pick(List<Double> hours, int naverUsed, int guessedUsed) {
    }

    /**
     * [11-21] 표본 구성 순서: ① 크롤링 직접 값 → ② 최소 표본 미만이면 네이버 요약 후기(걸러진 것) 보충
     * → ③ 그래도 미만이고, 전공 전체 크롤링 직접 값도 미만이면(B안) 하루시간 중앙값 추정값 보충.
     * 크롤링 직접 값이 충분하면 네이버·추정값은 쓰지 않는다 (기존 값 유지).
     */
    public static Pick pickWithNaver(List<Double> direct, List<Double> naver, List<Double> guessed,
                                     int allMajorDirectCount, int minSample) {
        List<Double> hours = new ArrayList<>(direct);
        int naverUsed = 0;
        int guessedUsed = 0;
        if (hours.size() < minSample && naver != null) {
            hours.addAll(naver);
            naverUsed = naver.size();
        }
        if (hours.size() < minSample && allMajorDirectCount < minSample && guessed != null) {
            hours.addAll(guessed);
            guessedUsed = guessed.size();
        }
        return new Pick(hours, naverUsed, guessedUsed);
    }

    /**
     * [11-21] 네이버 요약 후기 1건을 통계에 써도 되는지 (요약문 오인식 방지).
     * - 준비 기간 90일 초과: 필기 기간·재응시가 섞였을 가능성 → 제외
     * - 하루 3시간(180분) 초과: 전업 수험·과장 가능성 → 제외
     * - 요약문에 3년보다 오래된 "20xx년" 시험 언급: 카페 글은 작성일이 없어 대신 거른다 → 제외
     */
    public static boolean naverUsable(Integer prepDays, Integer dailyMinutes, String evidenceText, int currentYear) {
        if (prepDays != null && prepDays > 90) return false;
        if (dailyMinutes != null && dailyMinutes > 180) return false;
        if (evidenceText != null) {
            java.util.regex.Matcher m = java.util.regex.Pattern.compile("(20\\d{2})년").matcher(evidenceText);
            if (m.find() && Integer.parseInt(m.group(1)) < currentYear - 3) return false;
        }
        return true;
    }

    /** [11-21] 박스플롯 울타리 {Q1 - 1.5×IQR, Q3 + 1.5×IQR}. 값이 4개 미만이면 null (거르지 않음) */
    public static double[] iqrFences(List<Double> values) {
        if (values == null || values.size() < 4) return null;
        List<Double> s = new ArrayList<>(values);
        Collections.sort(s);
        double q1 = quantile(s, 0.25);
        double q3 = quantile(s, 0.75);
        double iqr = q3 - q1;
        return new double[]{q1 - 1.5 * iqr, q3 + 1.5 * iqr};
    }

    /** 정렬된 값의 사분위수 (선형 보간) */
    static double quantile(List<Double> sorted, double p) {
        double k = (sorted.size() - 1) * p;
        int f = (int) Math.floor(k);
        int c = Math.min(f + 1, sorted.size() - 1);
        return sorted.get(f) + (sorted.get(c) - sorted.get(f)) * (k - f);
    }

    /** STUDY_REFERENCE_STATS.stat_key 형식: 자격증:시험구분:과목(ALL):전공(ALL) */
    public static String statKey(long certId, String examType, Long subjectId, String major) {
        return certId + ":" + examType + ":" + (subjectId == null ? "ALL" : subjectId) + ":" + (major == null ? "ALL" : major);
    }

    public static double round2(double v) {
        return Math.round(v * 100.0) / 100.0;
    }
}
