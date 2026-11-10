package com.passpace.chat;

import com.passpace.chat.dto.ChatDtos.ExtractedCondition;
import com.passpace.chat.dto.ChatDtos.PlanNumbers;
import com.passpace.chat.dto.ChatDtos.StatsSummary;
import com.passpace.chat.service.NumberGuard;
import com.passpace.chat.service.PlanCalculator;
import com.passpace.chat.service.RegexConditionParser;
import com.passpace.chat.service.StatsCalculator;
import com.passpace.common.code.ExamType;
import com.passpace.common.code.MajorType;
import com.passpace.common.code.StudyMethod;
import com.passpace.common.stats.ReviewSample;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/** [동건] 챗봇 계산 로직 테스트 - DB·Spring·Ollama 없이 실행된다 */
class ChatLogicTest {

    private static final LocalDate TODAY = LocalDate.of(2026, 11, 6);

    @Test
    void 예시_질문에서_조건을_뽑는다() {
        ExtractedCondition c = new RegexConditionParser().parse(
                "비전공자가 정보처리기사 필기 준비중이다. 시험날은 3월 20일, 하루 2.5시간. 학습계획 세워줄 수 있는지?", TODAY);
        assertThat(c.majorType()).isEqualTo(MajorType.NON_MAJOR);
        assertThat(c.examType()).isEqualTo(ExamType.WRITTEN);
        assertThat(c.examDate()).isEqualTo(LocalDate.of(2027, 3, 20));   // 연도 없으면 다가오는 날짜
        assertThat(c.dailyMinutes()).isEqualTo(150);
    }

    @Test
    void 지난_날짜와_범위_밖_시간은_되묻는다() {
        RegexConditionParser p = new RegexConditionParser();
        assertThat(p.parse("2025년 3월 1일 시험", TODAY).examDatePast()).isTrue();
        assertThat(p.parse("하루 20시간 가능", TODAY).dailyMinutes()).isNull();
        assertThat(p.parse("하루 2시간 반", TODAY).dailyMinutes()).isEqualTo(150);
        assertThat(p.parse("하루 90분", TODAY).dailyMinutes()).isEqualTo(90);
    }

    @Test
    void 자주_쓰는_다른_표현도_읽는다() {
        RegexConditionParser p = new RegexConditionParser();
        assertThat(p.parse("하루 2~3시간 가능", TODAY).dailyMinutes()).isEqualTo(150);
        assertThat(p.parse("매일 1시간 반 정도", TODAY).dailyMinutes()).isEqualTo(90);
        assertThat(p.parse("하루에 두 시간씩", TODAY).dailyMinutes()).isEqualTo(120);
        assertThat(p.parse("주 14시간 가능", TODAY).dailyMinutes()).isEqualTo(120);
        assertThat(p.parse("필기 시험 3.20, 하루 2.5시간", TODAY).examDate()).isEqualTo(LocalDate.of(2027, 3, 20));
        assertThat(p.parse("비전공은 아니고 컴공입니다", TODAY).majorType()).isEqualTo(MajorType.MAJOR);
        assertThat(p.parse("필기 붙고 실기 준비중", TODAY).examType()).isEqualTo(ExamType.PRACTICAL);
    }

    @Test
    void 계획_질문이_아니면_구분한다() {
        RegexConditionParser p = new RegexConditionParser();
        assertThat(p.isPlanQuestion("고마워요!", p.parse("고마워요!", TODAY))).isFalse();
        assertThat(p.isPlanQuestion("실기 과목 뭐가 있어?", p.parse("실기 과목 뭐가 있어?", TODAY))).isFalse();
        assertThat(p.isPlanQuestion("3월 20일 시험 계획 세워줘", p.parse("3월 20일 시험 계획 세워줘", TODAY))).isTrue();
    }

    @Test
    void 남은기간과_단계와_과목배분을_계산한다() {
        PlanNumbers plan = new PlanCalculator().calculate(TODAY, LocalDate.of(2027, 3, 20), 150,
                List.of("소프트웨어 개발", "데이터베이스 구축", "프로그래밍 언어 활용", "정보시스템 구축관리"),
                Map.of("프로그래밍 언어 활용", 1, "데이터베이스 구축", 3), StudyMethod.PAST_EXAM);

        assertThat(plan.remainingDays()).isEqualTo(134);
        assertThat(plan.weeks()).isEqualTo(20);
        assertThat(plan.totalHours()).isEqualTo(335.0);
        assertThat(plan.phases()).hasSize(3);
        assertThat(plan.phases().stream().mapToInt(p -> p.days()).sum()).isEqualTo(134);
        assertThat(plan.phases().get(1).percent()).isEqualTo(55);                       // 기출 위주 → 기출 단계 55%
        assertThat(plan.phases().get(1).days()).isGreaterThan(plan.phases().get(0).days());
        assertThat(plan.phases()).extracting(p -> p.rangeLabel())
                .containsExactly("1~6주차", "7~16주차", "17~20주차");                 // 주차가 겹치지 않음
        assertThat(plan.subjects().get(0).subjectName()).isEqualTo("프로그래밍 언어 활용"); // 낯선 과목(1.3) 먼저
        assertThat(plan.subjects().get(3).subjectName()).isEqualTo("데이터베이스 구축");   // 익숙한 과목(0.7) 마지막
    }

    @Test
    void 통계는_합격자만_기준으로_계산하고_표본수를_확인한다() {
        List<ReviewSample> samples = new ArrayList<>();
        int[] daily = {120, 150, 180, 180, 240, 90, 150, 210, 180, 120};
        for (int i = 0; i < daily.length; i++) {
            samples.add(new ReviewSample(true, daily[i], null, 100 + i, "NON_MAJOR", "PAST_EXAM", null, "근거 " + i, "u" + i));
        }
        samples.add(new ReviewSample(false, 60, null, 100, "NON_MAJOR", "THEORY", null, null, null));

        StatsSummary s = new StatsCalculator().summarize(samples, 134, "테스트", 10);
        assertThat(s.available()).isTrue();
        assertThat(s.sampleSize()).isEqualTo(10);
        assertThat(s.avgDailyMinutes()).isEqualTo(162);    // (120+150+180+180+240+90+150+210+180+120)/10 = 162
        assertThat(s.medianDailyMinutes()).isEqualTo(165); // 정렬 후 5·6번째 150, 180 의 평균
        assertThat(s.failAvgDailyMinutes()).isEqualTo(60);
        assertThat(s.topMethodCode()).isEqualTo("PAST_EXAM");

        StatsSummary few = new StatsCalculator().summarize(samples.subList(0, 5), 134, "테스트", 10);
        assertThat(few.available()).isFalse();             // 10건 미만 → 통계 미사용
    }

    @Test
    void 자료에_없는_숫자를_찾아낸다() {
        NumberGuard guard = new NumberGuard();
        Set<String> allowed = guard.allowedNumbers("하루 2시간 30분(150분, 2.5시간), 평균 162분, 134일");
        assertThat(guard.findViolations("하루 2.5시간이면 134일 동안 충분합니다", allowed)).isEmpty();
        assertThat(guard.findViolations("합격률은 47%입니다", allowed)).containsExactly("47");
    }
}
