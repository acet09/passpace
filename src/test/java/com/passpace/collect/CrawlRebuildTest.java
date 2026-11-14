package com.passpace.collect;

import com.passpace.client.DataqScheduleClient;
import com.passpace.client.DataqScheduleClient.DataqRound;
import com.passpace.constant.ExamType;
import com.passpace.crawler.ListingParser.ListingLink;
import com.passpace.crawler.ReviewLinkFilter;
import com.passpace.domain.ExtractedReview;
import com.passpace.dto.collect.CertCountStatus;
import com.passpace.service.CertificateDetector;
import com.passpace.service.NaverSearchReviewCollectService;
import com.passpace.service.ReviewQualityChecker;
import com.passpace.service.RuleBasedReviewExtractor;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * [용성·11-14] 후기 수집 리빌딩 단위 테스트 - DB·Spring·네트워크 없이 실행된다.
 * dataq HTML 은 11-14 확인한 구조를 줄여 만든 샘플이다 → 실제 페이지 fixture 로 다시 확인할 것
 */
class CrawlRebuildTest {

    // ---------------- 자격증 4종 판별 ----------------

    @Test
    void 자격증_4종을_판별하고_비슷한_자격증은_제외한다() {
        assertThat(CertificateDetector.detect("컴활 1급 실기 합격 후기", "")).contains("CA1");
        assertThat(CertificateDetector.detect("컴퓨터활용능력 1급 필기 합격", "")).contains("CA1");
        assertThat(CertificateDetector.detect("컴활 2급 합격", "컴활 2급 실기")).isEmpty();          // 2급은 대상 아님
        assertThat(CertificateDetector.detect("ADsP 합격 후기", "")).contains("ADSP");
        assertThat(CertificateDetector.detect("데이터분석 준전문가 독학 합격", "")).contains("ADSP");
        assertThat(CertificateDetector.detect("ADP 필기 합격", "데이터분석 전문가")).isEmpty();     // ADP 는 대상 아님
        assertThat(CertificateDetector.detect("SQLP 합격", "")).isEmpty();
        assertThat(CertificateDetector.detect("정처기 ADsP 동시 합격", "")).isEmpty();               // 둘 이상 → 보류
        assertThat(CertificateDetector.detect("ADsP 합격", "정처기도 준비 중")).contains("ADSP");   // 제목 우선
        // 기존 2종 동작 유지
        assertThat(CertificateDetector.detect("정처기 필기 합격", "")).contains("1320");
        assertThat(CertificateDetector.detect("sqld합격 후기", "")).contains("SQLD");
    }

    @Test
    void 목록_필터가_컴활_ADsP_후기도_고른다() {
        List<ReviewLinkFilter.Candidate> found = ReviewLinkFilter.filter(List.of(
                new ListingLink("https://velog.io/@a/컴활-1급-합격", "컴활 1급 실기 합격 후기", null),
                new ListingLink("https://velog.io/@b/adsp", "ADsP 독학 합격", null),
                new ListingLink("https://velog.io/@c/com2", "컴활 2급 합격 후기", null),
                new ListingLink("https://velog.io/@d/adp", "ADP 필기 후기", null)));
        assertThat(found).extracting(ReviewLinkFilter.Candidate::label)
                .containsExactly("컴활 1급 실기 합격 후기", "ADsP 독학 합격");
    }

    // ---------------- 네이버 검색 API 응답 정리 ----------------

    @Test
    void 네이버_응답값을_정리한다() {
        assertThat(NaverSearchReviewCollectService.clean("<b>정처기</b> 합격 &amp; 후기")).isEqualTo("정처기 합격 & 후기");
        assertThat(NaverSearchReviewCollectService.blogUrl("https://blog.naver.com/abc_12/223456789012"))
                .isEqualTo("https://blog.naver.com/abc_12/223456789012");
        assertThat(NaverSearchReviewCollectService.blogUrl("https://blog.naver.com/PostView.naver?blogId=abc&logNo=223"))
                .isEqualTo("https://blog.naver.com/abc/223");
        assertThat(NaverSearchReviewCollectService.blogUrl("https://abc.tistory.com/31")).isNull();   // 네이버 블로그 아님
        assertThat(NaverSearchReviewCollectService.cafeUrl("http://cafe.naver.com/jpcafe/123456?art=xyz"))
                .isEqualTo("https://cafe.naver.com/jpcafe/123456");
        assertThat(NaverSearchReviewCollectService.postdate("20261110")).isEqualTo(LocalDate.of(2026, 11, 10));
        assertThat(NaverSearchReviewCollectService.bloggerId("blog.naver.com/abc_12", null)).isEqualTo("abc_12");
        assertThat(NaverSearchReviewCollectService.newsDate("Tue, 10 Nov 2026 09:00:00 +0900")).isEqualTo("2026-11-10");
    }

    @Test
    void 요약문은_VALID_로_저장하지_않는다() {
        ReviewQualityChecker checker = new ReviewQualityChecker();
        ExtractedReview r = new RuleBasedReviewExtractor().extract("컴활 1급 실기 합격", "한 달 동안 하루 2시간 공부해서 합격했어요");
        assertThat(checker.checkSnippet(r, "컴활 1급 실기 합격", LocalDate.of(2026, 11, 1)).reviewStatus()).isEqualTo("PENDING");
        assertThat(checker.checkSnippet(r, "컴활 1급 실기 합격", null).excludeReason()).isEqualTo("작성일 없음·요약문만 수집");
        assertThat(checker.checkSnippet(r, "협찬 받아 쓴 컴활 후기", null).reviewStatus()).isEqualTo("EXCLUDED");
        ExtractedReview tooShort = new ExtractedReview(true, ExamType.WRITTEN, null, null, null, null, null,
                BigDecimal.valueOf(2), null, null, false, null);
        assertThat(checker.checkSnippet(tooShort, "x", null).reviewStatus()).isEqualTo("EXCLUDED");
    }

    @Test
    void 컴활_ADsP_과목을_뽑는다() {
        ExtractedReview c = new RuleBasedReviewExtractor().extract("컴활 1급 실기 합격", "스프레드시트 실무보다 데이터베이스 실무가 어려웠다");
        assertThat(c.studySubjects()).contains("스프레드시트 실무", "데이터베이스 실무").doesNotContain("데이터베이스 구축");
        ExtractedReview a = new RuleBasedReviewExtractor().extract("ADsP 합격", "데이터분석 기획 과목이 제일 쉬웠다");
        assertThat(a.studySubjects()).contains("데이터분석 기획");
    }

    // ---------------- dataq 일정 페이지 ----------------

    @Test
    void dataq_날짜_범위를_나눈다() {
        String html = """
                <h3>2026년도 데이터자격검정 시험일정</h3>
                <h4>데이터분석 준전문가(ADsP)</h4>
                <table><tr><th>회차</th><th>원서접수</th><th>수험표발급</th><th>시험일</th><th>사전점수공개 및 재검토</th><th>합격발표</th></tr>
                <tr><td>제51회</td><td>9.28~10.2</td><td>10.16</td><td>10.31(토)</td><td>11.13~17</td><td>11.20</td></tr></table>
                <h4>SQL 개발자(SQLD)</h4>
                <table><tr><th>회차</th><th>원서접수</th><th>수험표발급</th><th>시험일</th><th>사전점수공개 및 재검토</th><th>합격발표</th></tr>
                <tr><td>제60회</td><td>1.5~9</td><td>2.20</td><td>3.7(토)</td><td>3.20~24</td><td>3.27</td></tr>
                <tr><td>제63회</td><td>10.12~16</td><td>10.30</td><td>11.14(토)</td><td>11.27~12.1</td><td>12.4</td></tr></table>""";
        List<DataqRound> rounds = DataqScheduleClient.parse(html, 2000);
        assertThat(rounds).hasSize(3);
        Map<String, DataqRound> by = new java.util.HashMap<>();
        rounds.forEach(r -> by.put(r.code() + r.item().roundNo(), r));
        var adsp = by.get("ADSP51").item();
        assertThat(adsp.examYear()).isEqualTo(2026);
        assertThat(adsp.regStart()).isEqualTo(LocalDate.of(2026, 9, 28));
        assertThat(adsp.regEnd()).isEqualTo(LocalDate.of(2026, 10, 2));
        assertThat(adsp.examStart()).isEqualTo(LocalDate.of(2026, 10, 31));
        assertThat(adsp.examEnd()).isEqualTo(adsp.examStart());
        assertThat(adsp.resultDate()).isEqualTo(LocalDate.of(2026, 11, 20));
        var sqld60 = by.get("SQLD60").item();
        assertThat(sqld60.regEnd()).isEqualTo(LocalDate.of(2026, 1, 9));          // 월이 빠진 끝값은 시작 월
        assertThat(sqld60.examType()).isEqualTo(ExamType.WRITTEN);
        assertThat(by.get("SQLD63").item().examStart()).isEqualTo(LocalDate.of(2026, 11, 14));
    }

    // ---------------- 자격증별 건수 ----------------

    @Test
    void 자격증별_건수를_묶는다() {
        Map<String, CertCountStatus.Row> rows = CertCountStatus.from(Map.of(
                "CA1|PENDING", 3, "CA1|UNREGISTERED", 2, "1320|VALID", 5, "1320|EXCLUDED", 1));
        assertThat(rows.get("1320")).isEqualTo(new CertCountStatus.Row(6, 5, 0, 1, 0));
        assertThat(rows.get("CA1")).isEqualTo(new CertCountStatus.Row(3, 0, 3, 0, 2));
    }
}
