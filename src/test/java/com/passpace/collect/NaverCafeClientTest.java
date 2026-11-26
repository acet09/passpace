package com.passpace.collect;

import com.passpace.client.NaverCafeClient;
import com.passpace.client.NaverCafeClient.CafeArticle;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

/** [용성·11-23] 네이버 카페 글 API 응답 해석 (네트워크 없이) */
class NaverCafeClientTest {

    @Test
    void 카페_글_주소_나누기() {
        assertThat(NaverCafeClient.parseUrl("https://cafe.naver.com/soojebi/189426")).containsExactly("soojebi", "189426");
        assertThat(NaverCafeClient.parseUrl("https://m.cafe.naver.com/yjbooks/1")).containsExactly("yjbooks", "1");
        assertThat(NaverCafeClient.parseUrl("https://blog.naver.com/a/1")).isNull();
    }

    @Test
    void v3_모양_응답에서_제목_본문_작성일() {
        String json = """
                {"result":{"article":{"id":189426,"subject":"정처기 필기 합격 후기",
                  "writeDate":1772668800000,
                  "contentHtml":"<div class=\\"se-main-container\\"><p>비전공, 하루 3시간씩 3주 공부했습니다.</p></div>"}}}""";
        Optional<CafeArticle> a = NaverCafeClient.parseArticle(json);
        assertThat(a).isPresent();
        assertThat(a.get().title()).isEqualTo("정처기 필기 합격 후기");
        assertThat(a.get().text()).isEqualTo("비전공, 하루 3시간씩 3주 공부했습니다.");
        assertThat(a.get().postedAt()).isEqualTo(LocalDate.of(2026, 3, 5));
    }

    @Test
    void 다른_감싸기_구조도_필드_이름으로_찾는다() {
        String json = """
                {"message":{"status":"200","result":{"article":{"subject":"SQLD 후기","writeDate":"2025-11-02 10:00",
                  "contentHtml":"<p>2주 준비</p>"}}}}""";
        Optional<CafeArticle> a = NaverCafeClient.parseArticle(json);
        assertThat(a).isPresent();
        assertThat(a.get().postedAt()).isEqualTo(LocalDate.of(2025, 11, 2));
    }

    @Test
    void 권한_없음_응답은_본문_없음() {
        String json = """
                {"result":{"errorCode":"0004","reason":"카페 멤버만 볼 수 있는 게시글입니다."}}""";
        assertThat(NaverCafeClient.parseArticle(json)).isEmpty();
        assertThat(NaverCafeClient.parseArticle("<html>로그인</html>")).isEmpty();
    }

    @Test
    void 쿠키가_없으면_시작하지_않는다() {
        NaverCafeClient none = new NaverCafeClient("", "yjbooks,soojebi", "test-agent", 0);
        assertThat(none.hasCookie()).isFalse();
        assertThat(none.clubs()).containsExactly("yjbooks", "soojebi");
        assertThat(new NaverCafeClient("NID_AUT=a; NID_SES=b", "yjbooks", "test-agent", 0).hasCookie()).isTrue();
    }
}
