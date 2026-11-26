package com.passpace.crawler;

import com.passpace.crawler.PostPageParser.PostPage;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;

import java.time.LocalDate;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [용성·11-23] 네이버 블로그 글 페이지(모바일 m.blog.naver.com)에서 본문·작성일·전재 금지 표시를 뽑는다. 네트워크 없이 테스트 가능.
 *
 *  - PC 주소(blog.naver.com/아이디/글번호)는 본문이 iframe 안에 있어서, 같은 글의 모바일 주소를 가져온다 → mobileUrl()
 *  - 본문 영역: 스마트에디터 ONE(.se-main-container) → 예전 에디터(#postViewArea, .post_ct 등) 순서
 *  - 작성일: 메타태그 → 날짜 표시 영역(.blog_date, .se_publishDate 등). 못 찾으면 null (네이버 검색 API 의 postdate 가 이미 저장돼 있음)
 *  - 댓글·공감·이웃 글 목록은 먼저 지운다. 본문은 메모리에서만 쓰고 저장하지 않는다 (PostPageParser 와 같은 원칙)
 */
public final class NaverBlogPageParser {

    private static final Pattern BLOG_PATH = Pattern.compile("^https?://(?:m\\.)?blog\\.naver\\.com/([A-Za-z0-9_\\-]+)/(\\d+)");

    private static final List<String> CONTENT = List.of(
            ".se-main-container", "#postViewArea", ".post_ct", "#viewTypeSelector", ".se_component_wrap", "div.post-view");
    private static final List<String> DATE = List.of(
            ".blog_date", ".se_publishDate", "span.date", "p.date", ".blog2_container .se_date");
    private static final String NOISE = String.join(",",
            "script", "style", "noscript", "nav", "footer", "form",
            "[class*=comment]", "[id*=comment]", "[class*=Comment]", "[class*=sympathy]", "[class*=related]",
            "[class*=recommend]", ".post_footer_contents", ".area_sympathy", ".post_btn", ".btn_post");

    private NaverBlogPageParser() {
    }

    /** blog.naver.com/아이디/글번호 → m.blog.naver.com/아이디/글번호. 네이버 블로그 글 주소가 아니면 null */
    public static String mobileUrl(String url) {
        if (url == null) return null;
        Matcher m = BLOG_PATH.matcher(url);
        return m.find() ? "https://m.blog.naver.com/" + m.group(1) + "/" + m.group(2) : null;
    }

    /** [11-23] 전재·복제 금지 표시 (카페 본문에도 같은 규칙을 쓰기 위해 공개) */
    public static boolean noReprint(String text) {
        return text != null && PostPageParser.NO_REPRINT.matcher(text).find();
    }

    public static PostPage parse(Document original, LocalDate today, int maxChars) {
        Document doc = original.clone();
        LocalDate postedAt = postedAt(doc, today);
        boolean noReprint = PostPageParser.NO_REPRINT.matcher(doc.body() == null ? "" : doc.body().text()).find();

        doc.select(NOISE).remove();
        Element area = content(doc);
        String text = area == null ? "" : area.text();
        if (text.length() > maxChars) text = text.substring(0, maxChars);

        Element og = doc.selectFirst("meta[property=og:title]");
        String title = og != null && !og.attr("content").isBlank() ? og.attr("content").strip() : doc.title();
        return new PostPage(title, text, postedAt, noReprint);
    }

    /** 본문 영역. 아는 선택자에 없으면 null (블로그 메뉴·이웃 글이 섞인 body 전체를 본문으로 쓰지 않는다) */
    static Element content(Document doc) {
        for (String css : CONTENT) {
            Element e = doc.selectFirst(css);
            if (e != null && !e.text().isBlank()) return e;
        }
        return null;
    }

    static LocalDate postedAt(Document doc, LocalDate today) {
        for (String css : List.of("meta[property=article:published_time]", "meta[property=og:regDate]",
                "meta[itemprop=datePublished]")) {
            Element e = doc.selectFirst(css);
            if (e != null) {
                LocalDate d = PostPageParser.toDate(e.attr("content"));
                if (d != null) return d;
            }
        }
        for (String css : DATE) {
            Element e = doc.selectFirst(css);
            if (e != null) {
                LocalDate d = PostPageParser.fromText(e.text(), today);
                if (d != null) return d;
            }
        }
        return null;
    }
}
