package com.passpace.collect;

import com.passpace.service.ReferenceMath;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** [용성·병합 2차] 참고 학습시간 계산 규칙 */
class ReferenceMathTest {

    @Test
    void 실측_총시간을_잠정_과목_비율로_나눈다() {
        // 잠정 과목 시간 11.13 / 5.71 / 2.78 / 4.31 (합 23.93) → 실측 총 120시간
        List<Double> split = ReferenceMath.splitByRatio(120, List.of(11.13, 5.71, 2.78, 4.31));
        assertThat(split).containsExactly(55.81, 28.63, 13.94, 21.61);
    }

    @Test
    void 잠정_비율이_없으면_똑같이_나눈다() {
        assertThat(ReferenceMath.splitByRatio(30, Arrays.asList(null, 5.0))).containsExactly(15.0, 15.0);
    }

    @Test
    void 후기_한_건의_시간은_총시간_없으면_준비일수와_하루시간으로() {
        assertThat(ReferenceMath.reviewHours(77.0, 70, 90)).isEqualTo(77.0);
        assertThat(ReferenceMath.reviewHours(null, 70, 90)).isEqualTo(105.0);
        assertThat(ReferenceMath.reviewHours(null, null, 90)).isNull();
    }

    @Test
    void 키_형식() {
        assertThat(ReferenceMath.statKey(1, "WRITTEN", null, null)).isEqualTo("1:WRITTEN:ALL:ALL");
        assertThat(ReferenceMath.statKey(2, "WRITTEN", 6L, "MAJOR")).isEqualTo("2:WRITTEN:6:MAJOR");
    }

    // ---------- [11-16] 중앙값 · 하루시간 추정 ----------

    @Test
    void 중앙값은_튀는_값에_끌려가지_않는다() {
        // 평균이면 (6+20+22+25+300)/5 = 74.6 이지만 중앙값은 22
        assertThat(ReferenceMath.median(List.of(300.0, 6.0, 22.0, 25.0, 20.0))).isEqualTo(22.0);
        assertThat(ReferenceMath.median(List.of(10.0, 20.0, 30.0, 41.0))).isEqualTo(25.0);
        assertThat(ReferenceMath.median(List.of())).isEqualTo(0.0);
    }

    @Test
    void 하루시간이_없는_3일컷은_같은_시험_하루시간_중앙값으로_추정한다() {
        // 3일 × 하루 240분(중앙값) = 12시간
        assertThat(ReferenceMath.reviewHoursWithFallback(null, 3, null, 240.0)).isEqualTo(12.0);
        // 총시간이나 하루시간이 있으면 기존 계산 그대로
        assertThat(ReferenceMath.reviewHoursWithFallback(30.0, 3, null, 240.0)).isEqualTo(30.0);
        assertThat(ReferenceMath.reviewHoursWithFallback(null, 10, 90, 240.0)).isEqualTo(15.0);
        // 보충값이 없거나 준비일수도 없으면 null (표본에서 빠짐)
        assertThat(ReferenceMath.reviewHoursWithFallback(null, 3, null, null)).isNull();
        assertThat(ReferenceMath.reviewHoursWithFallback(null, null, null, 240.0)).isNull();
    }

    @Test
    void 전공_전체_직접값이_10건_이상이면_어느_그룹도_추정값을_섞지_않는다() {
        // 11-19 이전: 전공 그룹(직접 8건)은 추정 34건을 섞어 42건 > 전공 전체 34건 이 되는 문제가 있었다
        List<Double> direct = List.of(10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0);
        List<Double> guessed = List.of(300.0, 400.0);
        assertThat(ReferenceMath.pickHours(direct, guessed, 34, 10)).hasSize(8).doesNotContain(300.0, 400.0);
    }

    @Test
    void 전공_전체_직접값도_10건_미만이면_추정값으로_채운다() {
        // 컴활 필기처럼 직접 값이 3건뿐이면 지금처럼 추정값을 허용
        List<Double> direct = List.of(10.0, 20.0, 30.0);
        List<Double> guessed = List.of(40.0, 50.0);
        assertThat(ReferenceMath.pickHours(direct, guessed, 3, 10)).containsExactly(10.0, 20.0, 30.0, 40.0, 50.0);
    }
}
