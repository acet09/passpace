package com.passpace.collect.discover;

import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [용성] 글 페이지(HTML)에서 본문·작성일·전재 금지 표시를 뽑는다. 네트워크 없이 테스트 가능.
 *
 *  - 댓글·추천글·내비게이션은 먼저 지운다 → 댓글 속 "저도 합격했어요" 같은 남의 말을 섞지 않음
 *  - 본문 영역은 사이트별 선택자 → article → main → body 순서
 *  - 작성일은 메타태그 → JSON-LD → time 태그 → (velog) 작성 정보 줄 순서. 못 찾으면 null
 */
public final class PostPageParser {

    /** 파싱 결과. text 는 메모리에서만 쓰고 저장하지 않는다 */
    public record PostPage(String title, String text, LocalDate postedAt, boolean noReprint) {
    }

    /** "무단 전재·복제 금지" 류 표시가 있으면 수집하지 않는다 (수집정보 목록 5.3) */
    static final Pattern NO_REPRINT = Pattern.compile(
            "무단\\s*(?:전재|복제|도용|배포|스크랩)|불펌|펌\\s*금지|퍼가(?:지|시지)\\s*마|스크랩\\s*금지|저작권\\s*침해\\s*시\\s*법적");

    private static final String NOISE = String.join(",",
            "script", "style", "noscript", "nav", "aside", "footer", "form",
            "[class*=comment]", "[id*=comment]", "[class*=Comment]", "[id*=Comment]",
            "#disqus_thread", ".another_category", ".container_postbtn", ".revenue_unit_wrap",
            "[class*=related]", "[class*=recommend]", "[class*=guestbook]");

    private static final List<String> VELOG_CONTENT = List.of("div.atom-one", "[class*=markdown-body]");
    private static final List<String> TISTORY_CONTENT = List.of(
            ".tt_article_useless_p_margin", ".entry-content", "#article-view", ".article-view", ".contents_style");

    private static final Pattern KOREAN_DATE = Pattern.compile("(20\\d{2})\\s*[년.\\-/]\\s*(\\d{1,2})\\s*[월.\\-/]\\s*(\\d{1,2})");
    private static final Pattern DAYS_AGO = Pattern.compile("(\\d{1,2})\\s*일\\s*전");
    private static final Pattern HOURS_AGO = Pattern.compile("\\d{1,2}\\s*(?:시간|분)\\s*전|방금");
    private static final Pattern LD_DATE = Pattern.compile("\"datePublished\"\\s*:\\s*\"([^\"]+)\"");

    private PostPageParser() {
    }

    public static PostPage parse(Document original, ReviewSite site, LocalDate today, int maxChars) {
        Document doc = original.clone();
        LocalDate postedAt = postedAt(doc, site, today);
        Element contentBefore = content(doc, site);
        boolean noReprint = NO_REPRINT.matcher(doc.body() == null ? "" : doc.body().text()).find();

        doc.select(NOISE).remove();
        Element area = content(doc, site);
        if (area == null) area = contentBefore;
        String text = area == null ? "" : area.text();
        if (text.length() > maxChars) text = text.substring(0, maxChars);

        String title = meta(doc, "meta[property=og:title]");
        if (title == null) title = doc.title();
        return new PostPage(title, text, postedAt, noReprint);
    }

    static Element content(Document doc, ReviewSite site) {
        for (String css : site == ReviewSite.VELOG ? VELOG_CONTENT : TISTORY_CONTENT) {
            Element e = doc.selectFirst(css);
            if (e != null && !e.text().isBlank()) return e;
        }
        for (String css : List.of("article", "main")) {
            Element e = doc.selectFirst(css);
            if (e != null && !e.text().isBlank()) return e;
        }
        return doc.body();
    }

    static LocalDate postedAt(Document doc, ReviewSite site, LocalDate today) {
        for (String css : List.of("meta[property=article:published_time]", "meta[name=article:published_time]",
                "meta[itemprop=datePublished]", "meta[property=og:regDate]", "meta[name=date]")) {
            LocalDate d = toDate(meta(doc, css));
            if (d != null) return d;
        }
        for (Element script : doc.select("script[type=application/ld+json]")) {
            Matcher m = LD_DATE.matcher(script.html());
            if (m.find()) {
                LocalDate d = toDate(m.group(1));
                if (d != null) return d;
            }
        }
        Element time = doc.selectFirst("time[datetime]");
        if (time != null) {
            LocalDate d = toDate(time.attr("datetime"));
            if (d != null) return d;
        }
        if (site == ReviewSite.VELOG) {
            // velog 글 머리의 "아이디 · 2025년 3월 2일" 줄
            for (Element info : doc.select("[class*=information], [class*=head-wrapper]")) {
                LocalDate d = fromText(info.ownText().isBlank() ? info.text() : info.ownText(), today);
                if (d != null) return d;
            }
        }
        return null;
    }

    static LocalDate fromText(String s, LocalDate today) {
        if (s == null) return null;
        Matcher m = KOREAN_DATE.matcher(s);
        if (m.find()) {
            try {
                return LocalDate.of(Integer.parseInt(m.group(1)), Integer.parseInt(m.group(2)), Integer.parseInt(m.group(3)));
            } catch (Exception ignored) {
                return null;
            }
        }
        m = DAYS_AGO.matcher(s);
        if (m.find()) return today.minusDays(Integer.parseInt(m.group(1)));
        if (HOURS_AGO.matcher(s).find()) return today;
        return null;
    }

    /** ISO-8601, yyyy-MM-dd, 티스토리 og:regDate(yyyyMMddHHmmss) */
    static LocalDate toDate(String s) {
        if (s == null || s.isBlank()) return null;
        String v = s.strip();
        try {
            return OffsetDateTime.parse(v).toLocalDate();
        } catch (Exception ignored) {
        }
        try {
            if (v.matches("\\d{14}") || v.matches("\\d{8}")) {
                return LocalDate.parse(v.substring(0, 8), DateTimeFormatter.BASIC_ISO_DATE);
            }
            return LocalDate.parse(v.substring(0, 10));
        } catch (Exception ignored) {
        }
        return fromText(v, LocalDate.now());
    }

    private static String meta(Document doc, String css) {
        Element e = doc.selectFirst(css);
        if (e == null) return null;
        String v = e.attr("content");
        return v.isBlank() ? null : v.strip();
    }
}
