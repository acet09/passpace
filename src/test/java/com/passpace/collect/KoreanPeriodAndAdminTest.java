package com.passpace.collect;

import com.passpace.collect.client.RobotsRules;
import com.passpace.collect.extract.RuleBasedReviewExtractor;
import com.passpace.collect.web.AdminLoginController;
import com.passpace.common.review.ExtractedReview;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** [용성] 4차 수정 테스트: 한글 기간 표현 · Crawl-delay · 관리자 이동 주소 (네트워크·DB 없이 실행) */
class KoreanPeriodAndAdminTest {

    private final RuleBasedReviewExtractor extractor = new RuleBasedReviewExtractor();

    private ExtractedReview ex(String text) {
        return extractor.extract("정처기 필기 합격 후기", text);
    }

    @Test
    void 한글_수로_쓴_준비기간을_읽는다() {
        assertThat(ex("세 달 동안 준비했습니다").prepDays()).isEqualTo(90);
        assertThat(ex("석달 공부").prepDays()).isEqualTo(90);
        assertThat(ex("두 주 동안 기출만 봤어요").prepDays()).isEqualTo(14);
        assertThat(ex("일주일 벼락치기로 붙었습니다").prepDays()).isEqualTo(7);
        assertThat(ex("열흘 만에 합격").prepDays()).isEqualTo(10);
        assertThat(ex("보름 정도 공부했어요").prepDays()).isEqualTo(15);
        assertThat(ex("이틀 벼락치기").prepDays()).isEqualTo(2);
        assertThat(ex("반년 준비한 끝에 합격").prepDays()).isEqualTo(180);
        assertThat(ex("한 달 동안 하루 3시간").prepDays()).isEqualTo(30);
    }

    @Test
    void 한글_수로_쓴_하루_공부시간을_읽는다() {
        assertThat(ex("하루 세 시간 반씩 공부").dailyMinutes()).isEqualTo(210);
        assertThat(ex("매일 두시간 공부").dailyMinutes()).isEqualTo(120);
        assertThat(ex("하루 3시간").dailyMinutes()).isEqualTo(180);      // 숫자 규칙이 먼저
    }

    @Test
    void 준비기간이_아닌_표현은_읽지_않는다() {
        assertThat(ex("시험 끝나고 한 달 뒤 발표가 났습니다").prepDays()).isNull();
        assertThat(ex("일주일에 3번 스터디").prepDays()).isNull();
        assertThat(ex("일주일에 한 번 모의고사").prepDays()).isNull();
        assertThat(ex("시험이 한 달 남았는데 걱정입니다").prepDays()).isNull();
        assertThat(ex("공부를 시작한 달부터 기록").prepDays()).isNull();
        assertThat(ex("이틀 후 결과 확인").prepDays()).isNull();
        assertThat(ex("보름 전에 접수했어요").prepDays()).isNull();
        assertThat(ex("두 달마다 시험이 있어요").prepDays()).isNull();
    }

    @Test
    void robots_Crawl_delay_를_읽는다() {
        RobotsRules r = RobotsRules.parse("User-agent: *\nCrawl-delay: 2\nDisallow: /manage", "PasspaceStudentBot");
        assertThat(r.crawlDelayMs()).isEqualTo(2000);
        assertThat(r.isAllowed("/manage/x")).isFalse();
        assertThat(r.isAllowed("/123")).isTrue();

        RobotsRules mine = RobotsRules.parse("User-agent: PasspaceStudentBot\nCrawl-delay: 0.5\n\nUser-agent: *\nCrawl-delay: 10",
                "PasspaceStudentBot");
        assertThat(mine.crawlDelayMs()).isEqualTo(500);                    // 우리 봇 묶음 우선
        assertThat(RobotsRules.parse("User-agent: *\nDisallow:", "PasspaceStudentBot").crawlDelayMs()).isZero();
    }

    @Test
    void 관리자_로그인_후_이동은_관리자_화면_안쪽만() {
        assertThat(AdminLoginController.safeRedirect("/admin/collect")).isEqualTo("/admin/collect");
        assertThat(AdminLoginController.safeRedirect("https://evil.example")).isEqualTo("/admin/collect");
        assertThat(AdminLoginController.safeRedirect("//evil.example")).isEqualTo("/admin/collect");
        assertThat(AdminLoginController.safeRedirect("/admin/login")).isEqualTo("/admin/collect");
        assertThat(AdminLoginController.safeRedirect(null)).isEqualTo("/admin/collect");
    }
}
