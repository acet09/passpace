package com.passpace.collect;

import com.passpace.crawler.NaverBlogPageParser;
import com.passpace.crawler.PostPageParser.PostPage;
import org.jsoup.Jsoup;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

/** [용성·11-23] 네이버 블로그 모바일 글 페이지 파싱 (네트워크 없이) */
class NaverBlogPageParserTest {

    private static final LocalDate TODAY = LocalDate.of(2026, 11, 23);

    @Test
    void PC_주소를_모바일_주소로() {
        assertThat(NaverBlogPageParser.mobileUrl("https://blog.naver.com/abc_12/223456789012"))
                .isEqualTo("https://m.blog.naver.com/abc_12/223456789012");
        assertThat(NaverBlogPageParser.mobileUrl("https://m.blog.naver.com/abc/1")).isEqualTo("https://m.blog.naver.com/abc/1");
        assertThat(NaverBlogPageParser.mobileUrl("https://cafe.naver.com/abc/1")).isNull();
        assertThat(NaverBlogPageParser.mobileUrl(null)).isNull();
    }

    @Test
    void 스마트에디터_본문과_작성일() {
        String html = """
                <html><head><meta property="og:title" content="정처기 필기 합격 후기"></head><body>
                <div class="blog_header">이웃 블로그 목록 하루 10시간</div>
                <p class="blog_date">2026. 3. 5. 10:20</p>
                <div class="se-main-container"><p>비전공자입니다. 하루 3시간씩 2주 공부해서 필기 합격했어요.</p></div>
                <div class="comment_area">저도 하루 8시간 했어요</div>
                </body></html>""";
        PostPage p = NaverBlogPageParser.parse(Jsoup.parse(html, "https://m.blog.naver.com/a/1"), TODAY, 5000);
        assertThat(p.title()).isEqualTo("정처기 필기 합격 후기");
        assertThat(p.text()).contains("하루 3시간씩 2주");
        assertThat(p.text().contains("8시간")).isFalse();      // 댓글은 지운다
        assertThat(p.text().contains("이웃 블로그")).isFalse(); // 본문 영역 밖은 쓰지 않는다
        assertThat(p.postedAt()).isEqualTo(LocalDate.of(2026, 3, 5));
        assertThat(p.noReprint()).isFalse();
    }

    @Test
    void 예전_에디터_본문() {
        String html = "<html><body><div id=\"postViewArea\">SQLD 합격! 한 달 준비했습니다.</div></body></html>";
        PostPage p = NaverBlogPageParser.parse(Jsoup.parse(html, "https://m.blog.naver.com/a/1"), TODAY, 5000);
        assertThat(p.text()).isEqualTo("SQLD 합격! 한 달 준비했습니다.");
        assertThat(p.postedAt()).isNull();
    }

    @Test
    void 본문_영역이_없으면_빈_본문() {
        String html = "<html><body><div class=\"error\">존재하지 않는 게시물입니다</div></body></html>";
        PostPage p = NaverBlogPageParser.parse(Jsoup.parse(html, "https://m.blog.naver.com/a/1"), TODAY, 5000);
        assertThat(p.text()).isEqualTo("");
    }

    @Test
    void 전재_금지_표시() {
        String html = "<html><body><div class=\"se-main-container\">합격 후기. 무단 전재 금지</div></body></html>";
        assertThat(NaverBlogPageParser.parse(Jsoup.parse(html, "https://m.blog.naver.com/a/1"), TODAY, 5000).noReprint()).isTrue();
    }
}
