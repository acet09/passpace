package com.passpace.collect;

import com.passpace.collect.extract.RuleBasedReviewExtractor;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** [용성] 6차 보강: 하루 공부시간 표현 (범위·사이 말·평일/주말·주 단위) + 오인식 방지 */
class DailyTimeRuleTest {

    private final RuleBasedReviewExtractor extractor = new RuleBasedReviewExtractor();

    private Integer daily(String text) {
        return extractor.extract("정처기 필기 합격 후기", text).dailyMinutes();
    }

    @Test
    void 범위는_평균으로_읽는다() {
        assertThat(daily("하루 3~4시간씩 공부했어요")).isEqualTo(210);
        assertThat(daily("매일 2-3시간 정도 투자")).isEqualTo(150);
        assertThat(daily("하루에 1~2시간 반")).isEqualTo(120);
    }

    @Test
    void 사이에_말이_낀_표현을_읽는다() {
        assertThat(daily("하루에 꾸준히 2시간 공부")).isEqualTo(120);
        assertThat(daily("매일 퇴근 후 3시간씩")).isEqualTo(180);
        assertThat(daily("퇴근 후 2시간씩 기출을 풀었습니다")).isEqualTo(120);
        assertThat(daily("일과 후 1시간 30분")).isEqualTo(90);
    }

    @Test
    void 평일_주말을_나눈_표현은_주간_평균() {
        assertThat(daily("평일 2시간, 주말 6시간 공부")).isEqualTo(189);       // (2*5 + 6*2) / 7 = 3.14h
        assertThat(daily("평일에는 1~2시간 주말에는 5시간")).isEqualTo(150);   // (1.5*5 + 5*2) / 7 = 2.5h
    }

    @Test
    void 주_단위는_하루_평균으로() {
        assertThat(daily("일주일에 14시간 정도 공부")).isEqualTo(120);
        assertThat(daily("주 21시간 목표로")).isEqualTo(180);
    }

    @Test
    void 기존_표현은_그대로() {
        assertThat(daily("하루 2시간 30분")).isEqualTo(150);
        assertThat(daily("하루 90분")).isEqualTo(90);
        assertThat(daily("하루 세 시간 반")).isEqualTo(210);
    }

    @Test
    void 공부시간이_아닌_표현은_읽지_않는다() {
        assertThat(daily("하루 만에 2시간짜리 강의를 들었다")).isNull();
        assertThat(daily("시험 시간 2시간 동안 집중")).isNull();
        assertThat(daily("하루 2시간짜리 인강")).isNull();
        assertThat(daily("2주 동안 30시간")).isNull();                   // 2주 합계 → 주 단위 아님
        assertThat(daily("주말에 5시간")).isNull();                        // 주말만 → 하루 평균 아님
        assertThat(daily("주 3회 스터디")).isNull();
        assertThat(daily("매일 아침. 2시간 걸려 출근")).isNull();          // 문장 경계 넘지 않음
    }
}
