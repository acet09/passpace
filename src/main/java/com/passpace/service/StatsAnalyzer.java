package com.passpace.service;

import com.passpace.dto.chat.ChatDtos.StatsSummary;
import com.passpace.constant.ExamType;
import com.passpace.constant.MajorType;
import com.passpace.repository.ReviewStatsQuery;
import com.passpace.domain.StatsCondition;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/**
 * [동건] 처리 ③ 유사 집단 찾기
 * 표본이 10건(min-sample) 미만이면 조건을 한 단계씩 넓힌다.
 *   1단계: 같은 전공 구분 · 준비 기간이 남은 일수의 0.5~1.5배
 *   2단계: 같은 전공 구분 · 0.3~3배
 *   3단계: 전공 구분 무관 · 0.3~3배
 * 그래도 부족하면 available=false → 답변에서 "통계 미사용"을 알린다 (기획안 7.1.4).
 *
 * 후기 조회는 공통 계약 ReviewStatsQuery 로만 한다 (구현은 용성, fake 프로필에서는 가짜 구현).
 */
@Component
public class StatsAnalyzer {

    private final ReviewStatsQuery reviewStatsQuery;
    private final StatsCalculator calculator = new StatsCalculator();
    private final int minSample;

    public StatsAnalyzer(ReviewStatsQuery reviewStatsQuery, @Value("${passpace.stats.min-sample:10}") int minSample) {
        this.reviewStatsQuery = reviewStatsQuery;
        this.minSample = minSample;
    }

    public StatsSummary analyze(long certificationId, ExamType examType, MajorType majorType, int remainingDays) {
        List<Level> levels = List.of(
                new Level(majorType, 0.5, 1.5, "같은 전공 구분 · 준비기간 0.5~1.5배"),
                new Level(majorType, 0.3, 3.0, "같은 전공 구분 · 준비기간 0.3~3배"),
                new Level(null, 0.3, 3.0, "전공 구분 전체 · 준비기간 0.3~3배"));
        StatsSummary last = null;
        for (Level level : levels) {
            int minDays = Math.max(1, (int) Math.floor(remainingDays * level.minRatio()));
            int maxDays = Math.max(minDays, (int) Math.ceil(remainingDays * level.maxRatio()));
            last = calculator.summarize(reviewStatsQuery.findSamples(
                    new StatsCondition(certificationId, examType, level.major(), minDays, maxDays)),
                    remainingDays, level.label(), minSample);
            if (last.available()) return last;
        }
        return last;
    }

    public int getMinSample() {
        return minSample;
    }

    private record Level(MajorType major, double minRatio, double maxRatio, String label) {
    }
}
