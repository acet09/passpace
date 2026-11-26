package com.passpace.collect;

import com.passpace.domain.ExtractedReview;
import com.passpace.service.RuleBasedReviewExtractor;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * [용성·11-23] "시간 정보 없음"으로 빠진 후기 표본(티스토리·velog 18건)에서 찾은 표현.
 * 새 규칙은 기존 규칙이 값을 못 찾았을 때만 쓰인다 → 기존 결과는 바뀌지 않는다.
 */
class MissedTimeRuleTest {

    private final RuleBasedReviewExtractor extractor = new RuleBasedReviewExtractor();

    private ExtractedReview read(String text) {
        return extractor.extract("합격 후기", text);
    }

    @Test
    void 기간_뒤에_의가_붙은_표현() {
        assertThat(read("4월 26일 ~ 5월 17일 약 3주의 기간동안 공부 분배는 다음과 같이 했습니다.").prepDays()).isEqualTo(21);
        assertThat(read("10일 정도의 준비 기간이 있었다").prepDays()).isEqualTo(10);
    }

    @Test
    void 기간_범위는_평균() {
        assertThat(read("그래서 기간은 1-2주로 잡았고").prepDays()).isEqualTo(11);     // 1.5주 = 10.5일
        assertThat(read("준비 기간 2-4개월").prepDays()).isEqualTo(120);           // 기존 규칙이 "4개월"을 먼저 읽음 (기존 결과 유지)
    }

    @Test
    void 며칠_전부터_준비() {
        assertThat(read("시험 7일 전부터 준비하고자 했는데, 회사 일정 때문에 많이 못 했다.").prepDays()).isEqualTo(7);
        assertThat(read("2주 전부터 공부 시작").prepDays()).isEqualTo(14);
    }

    @Test
    void 공부할_수_있는_날() {
        assertThat(read("8월 22일 시험까지 공부할 수 있는 날은 7일.").prepDays()).isEqualTo(7);
    }

    @Test
    void 날짜_범위() {
        assertThat(read("제대로 된 공부는 4월 26일부터 시험 전날인 5월 17일까지 공부 했습니다.").prepDays()).isEqualTo(21);
        assertThat(read("12월 20일부터 1월 10일까지 퇴근하고 공부").prepDays()).isEqualTo(21);           // 해를 넘김
    }

    @Test
    void 날짜_범위라도_시험_일정이면_준비기간_아님() {
        assertThat(read("원서 접수 기간은 4월 1일 ~ 4월 5일입니다. 공부 열심히 하세요").prepDays()).isNull();
        assertThat(read("4월 1일부터 4월 5일까지 접수, 준비물 챙기기").prepDays()).isNull();
    }

    @Test
    void 시험_전날_공부는_1일() {
        assertThat(read("결국 하루 전에 급하게 공부한 인간의 후기입니다.").prepDays()).isEqualTo(1);
        assertThat(read("하루 전에 개념을 슥 훑고 가서 당일에 긴장을 했다").prepDays()).isEqualTo(1);
        assertThat(read("혹시 저처럼 전날 벼락치기를 하시는 분이 계시다면").prepDays()).isEqualTo(1);
    }

    @Test
    void 전날이라도_공부가_아니면_무시() {
        assertThat(read("시험 전날 준비물을 챙겼다").prepDays()).isNull();
        assertThat(read("ADsP는 20일 당일에 서버가 터졌는지 하루 전에 접수가 안 됐다").prepDays()).isNull();
    }

    @Test
    void 벼락치기_시간은_총_공부시간() {
        ExtractedReview r = read("[46회 ADsP] 1일 (10시간) 벼락치기 후기");
        assertThat(r.prepDays()).isEqualTo(1);
        assertThat(r.totalHours()).isEqualByComparingTo("10");
        assertThat(read("SQLD 12시간 벼락치기로 합격").totalHours()).isEqualByComparingTo("12");
        assertThat(read("시험전날 잠을 안 자고 14시간 정도 공부했습니다.").totalHours()).isEqualByComparingTo("14");
    }

    @Test
    void 벼락치기_강의_이름은_공부시간이_아님() {
        assertThat(read("\"핵심요약 5시간 벼락치기 특강\" 추천").totalHours()).isNull();
    }

    @Test
    void 기존_규칙이_찾으면_그대로() {
        // "2달" 은 기존 규칙(60일)이 먼저 읽는다. 뒤의 "하루 전에 공부" 로 바뀌지 않는다
        assertThat(read("두 달 동안 공부했고 시험 하루 전에 공부를 마무리").prepDays()).isEqualTo(60);
        // "총 30시간" 은 기존 규칙이 먼저 읽는다
        assertThat(read("총 30시간 공부, 전날 5시간 벼락치기").totalHours()).isEqualByComparingTo("30");
    }
}
