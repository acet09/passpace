package com.passpace.collect;

import com.passpace.collect.client.RobotsRules;
import com.passpace.collect.discover.ListingParser;
import com.passpace.collect.discover.PostPageParser;
import com.passpace.collect.discover.PostPageParser.PostPage;
import com.passpace.collect.discover.ReviewLinkFilter;
import com.passpace.collect.discover.ReviewLinkFilter.Candidate;
import com.passpace.collect.discover.ReviewSite;
import com.passpace.collect.discover.UrlText;
import com.passpace.collect.extract.CertificateDetector;
import com.passpace.collect.extract.ReviewQualityChecker;
import com.passpace.collect.extract.ReviewQualityChecker.PageContext;
import com.passpace.collect.extract.RuleBasedReviewExtractor;
import com.passpace.common.code.ExamType;
import com.passpace.common.review.ExtractedReview;
import org.jsoup.Jsoup;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * [용성] 크롤링 정책(기획안 7.1) 단위 테스트 - 네트워크·DB 없이 fixture HTML 로 실행.
 * fixture 는 velog·티스토리 화면 구조를 흉내 낸 예시이며 실제 글이 아니다.
 */
class ReviewCrawlPolicyTest {

    private static final LocalDate TODAY = LocalDate.of(2026, 11, 8);
    private final RuleBasedReviewExtractor extractor = new RuleBasedReviewExtractor();
    private final ReviewQualityChecker checker = new ReviewQualityChecker();

    private static String fx(String name) throws IOException {
        try (InputStream in = ReviewCrawlPolicyTest.class.getResourceAsStream("/collect-fixtures/" + name)) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    // ---------------- 수집 대상 사이트·주소 ----------------

    @Test
    void 허용_사이트의_개별_글_주소만_수집_대상이다() {
        String velog = UrlText.canonical("http://velog.io/@devkim/정처기-합격/?utm=1#c");
        assertThat(velog).startsWith("https://velog.io/@devkim/%EC%A0%95");
        assertThat(ReviewSite.of(velog)).contains(ReviewSite.VELOG);
        assertThat(ReviewSite.VELOG.isPostUrl(velog)).isTrue();
        assertThat(ReviewSite.VELOG.isPostUrl(UrlText.canonical("https://velog.io/tags/정처기"))).isFalse();

        assertThat(ReviewSite.TISTORY.isPostUrl("https://abc.tistory.com/31")).isTrue();
        assertThat(ReviewSite.TISTORY.isPostUrl("https://abc.tistory.com/manage/post/9")).isFalse();
        assertThat(ReviewSite.TISTORY.isPostUrl("https://abc.tistory.com/category/x")).isFalse();

        assertThat(ReviewSite.of("https://blog.naver.com/x/1")).isEmpty();     // 네이버는 대상 아님
        assertThat(ReviewSite.of("https://www.tistory.com/x")).isEmpty();
    }

    @Test
    void 목록에서_자격증_후기_글만_후보로_고른다() throws IOException {
        List<Candidate> velog = ReviewLinkFilter.filter(
                ListingParser.parse(fx("velog_tag.html"), "https://velog.io/tags/%EC%A0%95%EC%B2%98%EA%B8%B0"));
        // 정처기 후기 1 + 주소에 sqld-합격이 있는 글 1. React 글·태그·작성자 목록·외부 링크·산업기사 글은 제외
        assertThat(velog).extracting(Candidate::url).containsExactly(
                UrlText.canonical("https://velog.io/@devkim/정처기-필기-합격-후기"),
                "https://velog.io/@park/sqld-%ED%95%A9%EA%B2%A9");

        List<Candidate> rss = ReviewLinkFilter.filter(
                ListingParser.parse(fx("tistory_rss.xml"), "https://studyblog.tistory.com/rss"));
        assertThat(rss).hasSize(2);                                              // 관리 페이지·무관한 글 제외
        assertThat(rss.get(0).listedDate()).isEqualTo(LocalDate.of(2025, 9, 30));
    }

    @Test
    void velog_태그목록의_내장_데이터에서_글을_찾는다() throws IOException {
        // velog 태그 페이지는 <a> 링크 대신 페이지 안 데이터에 글 목록을 넣는다 (2026-11-08 구조)
        List<Candidate> found = ReviewLinkFilter.filter(
                ListingParser.parse(fx("velog_tag_data.html"), "https://velog.io/tags/%EC%A0%95%EC%B2%98%EA%B8%B0"));
        assertThat(found).extracting(Candidate::url).containsExactly(
                UrlText.canonical("https://velog.io/@writer_a/정보처리기사-실기-합격-후기"),
                UrlText.canonical("https://velog.io/@writer-c/sqld-합격"));
        assertThat(found.get(0).listedDate()).isEqualTo(LocalDate.of(2026, 10, 30));
        assertThat(found.get(0).label()).isEqualTo("정보처리기사 실기 합격 후기 \"일주일\" 벼락치기");
    }

    @Test
    void velog_검색결과_데이터에서_글을_찾는다() throws IOException {
        // velog 검색 페이지는 글(Post)과 작성자(User)가 따로 저장된 구조 (2026-11-08)
        List<Candidate> found = ReviewLinkFilter.filter(
                ListingParser.parse(fx("velog_search_data.html"), "https://velog.io/search?q=%EC%A0%95%EC%B2%98%EA%B8%B0"));
        assertThat(found).extracting(Candidate::url).containsExactly(
                UrlText.canonical("https://velog.io/@writer_a/정처기-합격-후기"),
                UrlText.canonical("https://velog.io/@writer_b/sqld-합격"));
        assertThat(found.get(0).listedDate()).isEqualTo(LocalDate.of(2024, 8, 13));
    }

    @Test
    void robots_규칙을_지킨다() {
        RobotsRules r = RobotsRules.parse("""
                User-agent: *
                Disallow: /search
                Allow: /search/ok$
                Disallow: /*?page=

                User-agent: Googlebot
                Disallow: /
                """, "PasspaceStudentBot");
        assertThat(r.isAllowed("/31")).isTrue();
        assertThat(r.isAllowed("/search/x")).isFalse();
        assertThat(r.isAllowed("/search/ok")).isTrue();           // 더 긴 Allow 가 이김
        assertThat(r.isAllowed("/category?page=2")).isFalse();    // * 지원

        RobotsRules mine = RobotsRules.parse("User-agent: *\nAllow: /\nUser-agent: PasspaceStudentBot\nDisallow: /\n",
                "PasspaceStudentBot");
        assertThat(mine.isAllowed("/a")).isFalse();               // 우리 봇 전용 규칙이 우선
    }

    // ---------------- 글 페이지 ----------------

    @Test
    void 본문만_읽고_댓글은_섞지_않으며_작성일을_찾는다() throws IOException {
        PostPage v = PostPageParser.parse(Jsoup.parse(fx("velog_post.html")), ReviewSite.VELOG, TODAY, 4000);
        assertThat(v.postedAt()).isEqualTo(LocalDate.of(2026, 3, 20));
        assertThat(v.text()).contains("하루 2시간 30분").doesNotContain("10시간");

        PostPage t = PostPageParser.parse(Jsoup.parse(fx("tistory_post.html")), ReviewSite.TISTORY, TODAY, 4000);
        assertThat(t.postedAt()).isEqualTo(LocalDate.of(2025, 9, 30));
        assertThat(t.text()).doesNotContain("15시간").doesNotContain("실기 후기");

        assertThat(PostPageParser.parse(Jsoup.parse(fx("noreprint_post.html")), ReviewSite.TISTORY, TODAY, 4000)
                .noReprint()).isTrue();
    }

    @Test
    void 자격증을_구분한다() {
        assertThat(CertificateDetector.detect("정처기 필기 합격", "")).contains("1320");
        assertThat(CertificateDetector.detect("sqld합격 후기", "")).contains("SQLD");
        assertThat(CertificateDetector.detect("정보처리산업기사 합격", "정보처리산업기사")).isEmpty();
        assertThat(CertificateDetector.detect("정처기 SQLD 동시 합격", "")).isEmpty();      // 둘 다 → 보류
        assertThat(CertificateDetector.detect("SQLD 합격", "정처기도 준비 중")).contains("SQLD");  // 제목 우선
    }

    @Test
    void 근거는_원문_문장이_아니라_요약문이다() throws IOException {
        PostPage v = PostPageParser.parse(Jsoup.parse(fx("velog_post.html")), ReviewSite.VELOG, TODAY, 4000);
        ExtractedReview r = extractor.extract(v.title(), v.text());
        assertThat(r.evidenceText())
                .isEqualTo("비전공 · 2026년 1회 필기 합격 · 준비 60일 · 하루 2시간 30분 · 기출 위주 · 언급 과목: 데이터베이스 구축 · 합격 인증 언급");
        assertThat(r.evidenceText()).doesNotContain("반복했어요");

        PostPage t = PostPageParser.parse(Jsoup.parse(fx("tistory_post.html")), ReviewSite.TISTORY, TODAY, 4000);
        ExtractedReview sqld = RuleBasedReviewExtractor.withExamType(extractor.extract(t.title(), t.text()), ExamType.WRITTEN);
        assertThat(sqld.studySubjects()).isEqualTo("데이터 모델링의 이해,SQL 기본 및 활용");
        assertThat(sqld.evidenceText()).contains("필기 합격");
    }

    // ---------------- 정책 검사 ----------------

    @Test
    void 작성일_3년_전재금지_날짜모순을_걸러낸다() throws IOException {
        PostPage v = PostPageParser.parse(Jsoup.parse(fx("velog_post.html")), ReviewSite.VELOG, TODAY, 4000);
        ExtractedReview r = extractor.extract(v.title(), v.text());     // 2026년 1회 필기 합격

        assertThat(checker.check(r, v.text(), new PageContext(v.postedAt(), TODAY, false, LocalDate.of(2026, 2, 15)))
                .reviewStatus()).isEqualTo("VALID");
        assertThat(checker.check(r, v.text(), new PageContext(v.postedAt(), TODAY, true, null)).excludeReason())
                .startsWith("무단 전재");
        assertThat(checker.check(r, v.text(), new PageContext(null, TODAY, false, null)).excludeReason())
                .startsWith("작성일 확인 불가");
        assertThat(checker.check(r, v.text(), new PageContext(LocalDate.of(2023, 11, 7), TODAY, false, null)).excludeReason())
                .startsWith("작성일이 3년");
        assertThat(checker.check(r, v.text(), new PageContext(LocalDate.of(2025, 12, 1), TODAY, false, null)).excludeReason())
                .contains("응시 연도");
        assertThat(checker.check(r, v.text(), new PageContext(LocalDate.of(2026, 2, 1), TODAY, false, LocalDate.of(2026, 2, 15)))
                .excludeReason()).contains("공식 시험일");

        ExtractedReview noType = extractor.extract("정처기 합격", "정처기 합격 한 달 동안 하루 3시간");
        assertThat(checker.check(noType, "x", new PageContext(TODAY, TODAY, false, null)).reviewStatus()).isEqualTo("PENDING");
    }
}
