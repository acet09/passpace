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
}
