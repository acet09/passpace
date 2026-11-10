package com.passpace.collect.discover;

import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.jsoup.parser.Parser;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [용성] 목록 페이지(태그 페이지 HTML) 또는 피드(RSS·Atom)에서 글 링크를 뽑는다.
 * 네트워크 없이 문자열만 다루므로 단위 테스트가 가능하다.
 */
public final class ListingParser {

    /** 목록에서 찾은 링크 1개. postedAt 은 피드가 알려 준 작성일(없으면 null) */
    public record ListingLink(String url, String label, LocalDate postedAt) {
    }

    private ListingParser() {
    }

    public static List<ListingLink> parse(String body, String baseUrl) {
        String head = body == null ? "" : body.stripLeading();
        if (head.startsWith("<?xml") || head.startsWith("<rss") || head.startsWith("<feed")) {
            return parseFeed(body);
        }
        return parseHtml(body == null ? "" : body, baseUrl);
    }

    static List<ListingLink> parseFeed(String xml) {
        Document doc = Jsoup.parse(xml, "", Parser.xmlParser());
        List<ListingLink> links = new ArrayList<>();
        for (Element item : doc.select("item")) {                     // RSS 2.0
            String link = textOf(item, "link");
            if (link.isEmpty()) continue;
            links.add(new ListingLink(link, textOf(item, "title"), parseDate(textOf(item, "pubDate"))));
        }
        for (Element entry : doc.select("entry")) {                   // Atom
            Element a = entry.selectFirst("link[href]");
            if (a == null) continue;
            String published = textOf(entry, "published");
            links.add(new ListingLink(a.attr("href"), textOf(entry, "title"),
                    parseDate(published.isEmpty() ? textOf(entry, "updated") : published)));
        }
        return links;
    }

    static List<ListingLink> parseHtml(String html, String baseUrl) {
        Document doc = Jsoup.parse(html, baseUrl);
        Map<String, ListingLink> byUrl = new LinkedHashMap<>();
        for (Element a : doc.select("a[href]")) {
            String url = a.absUrl("href");
            if (url.isEmpty()) continue;
            String label = a.text();
            if (label.isBlank()) label = a.attr("title");
            // 이미지 카드처럼 글자가 없는 링크: 부모가 이 링크 하나만 감싸고 있을 때만 부모 글자를 제목으로 쓴다
            // (목록 전체를 감싼 부모의 글자를 쓰면 엉뚱한 글이 키워드 검사를 통과한다)
            if (label.isBlank() && a.parent() != null && a.parent().select("a[href]").size() == 1) {
                label = a.parent().text();
            }
            if (label.length() > 200) label = label.substring(0, 200);
            ListingLink old = byUrl.get(url);
            if (old == null || old.label().isBlank()) {
                byUrl.put(url, new ListingLink(url, label, null));
            }
        }
        if (baseUrl != null && baseUrl.startsWith("https://velog.io/")) {
            for (ListingLink link : parseVelogData(html)) {
                byUrl.putIfAbsent(link.url(), link);
            }
            for (ListingLink link : parseVelogSearchData(html)) {
                byUrl.putIfAbsent(link.url(), link);
            }
        }
        return new ArrayList<>(byUrl.values());
    }

    // velog 태그 목록은 글 링크를 <a> 로 그리지 않고, 페이지 안의 데이터(self.__next_f.push)에 글 목록을 넣어 둔다.
    // 그 데이터에서 제목·주소(url_slug)·작성자·작성일(released_at)을 읽는다. (2026-11-08 화면 구조 기준)
    private static final String Q = "\\\\?\"";      // 따옴표 앞 역슬래시가 있을 수도, 없을 수도 있음
    private static final Pattern VELOG_POST = Pattern.compile(
            Q + "title" + Q + ":" + Q + "(.*?)" + Q + "," + Q + "url_slug" + Q + ":" + Q + "(.*?)" + Q);
    private static final Pattern VELOG_USER = Pattern.compile(Q + "username" + Q + ":" + Q + "([^\"\\\\]+)" + Q);
    private static final Pattern VELOG_RELEASED = Pattern.compile(Q + "released_at" + Q + ":" + Q + "([0-9T:.\\-Z]+)" + Q);

    static List<ListingLink> parseVelogData(String html) {
        List<ListingLink> links = new ArrayList<>();
        Matcher m = VELOG_POST.matcher(html);
        List<int[]> spans = new ArrayList<>();
        List<String[]> found = new ArrayList<>();
        while (m.find()) {
            spans.add(new int[]{m.end()});
            found.add(new String[]{m.group(1), m.group(2)});
        }
        for (int i = 0; i < found.size(); i++) {
            int from = spans.get(i)[0];
            int to = i + 1 < spans.size() ? spans.get(i + 1)[0] : Math.min(html.length(), from + 5000);
            String region = html.substring(from, to);
            Matcher u = VELOG_USER.matcher(region);
            if (!u.find()) continue;
            Matcher r = VELOG_RELEASED.matcher(region);
            String title = found.get(i)[0].replace("\\", "");
            String slug = found.get(i)[1];
            links.add(new ListingLink("https://velog.io/@" + u.group(1) + "/" + slug, title,
                    r.find() ? parseDate(r.group(1)) : null));
        }
        return links;
    }

    // velog 검색 페이지(/search?q=)는 데이터 구조가 다르다: 글(Post)에는 작성자 ID 만 있고,
    // 작성자 아이디(username)는 따로 있는 User 항목에 있다. (2026-11-08 화면 구조 기준)
    private static final Pattern SEARCH_USER = Pattern.compile(
            Q + "User:([0-9a-f-]{36})" + Q + ":\\{" + Q + "id" + Q + ":" + Q + "[0-9a-f-]{36}" + Q + ","
                    + Q + "username" + Q + ":" + Q + "([^\"\\\\]+)");
    private static final Pattern SEARCH_POST = Pattern.compile(
            Q + "title" + Q + ":" + Q + "((?:(?!" + Q + ",).)*?)" + Q + ","
                    + "(?:(?!" + Q + "title" + Q + ":).)*?" + Q + "id" + Q + ":" + Q + "User:([0-9a-f-]{36})" + Q
                    + "(?:(?!" + Q + "title" + Q + ":).)*?" + Q + "url_slug" + Q + ":" + Q + "((?:(?!" + Q + ").)+)" + Q + ","
                    + Q + "released_at" + Q + ":" + Q + "([0-9T:.\\-Z]+)");

    static List<ListingLink> parseVelogSearchData(String html) {
        Map<String, String> users = new LinkedHashMap<>();
        Matcher um = SEARCH_USER.matcher(html);
        while (um.find()) users.putIfAbsent(um.group(1), um.group(2));
        List<ListingLink> links = new ArrayList<>();
        if (users.isEmpty()) return links;
        Matcher pm = SEARCH_POST.matcher(html);
        while (pm.find()) {
            String username = users.get(pm.group(2));
            if (username == null) continue;
            links.add(new ListingLink("https://velog.io/@" + username + "/" + pm.group(3),
                    pm.group(1).replace("\\", ""), parseDate(pm.group(4))));
        }
        return links;
    }

    private static String textOf(Element parent, String tag) {
        Element e = parent.selectFirst(tag);
        return e == null ? "" : e.text().strip();
    }

    /** RFC 1123(RSS) 또는 ISO-8601(Atom) 날짜 → LocalDate. 모르면 null */
    static LocalDate parseDate(String s) {
        if (s == null || s.isBlank()) return null;
        try {
            return ZonedDateTime.parse(s.strip(), DateTimeFormatter.RFC_1123_DATE_TIME.withLocale(Locale.ENGLISH)).toLocalDate();
        } catch (Exception ignored) {
        }
        try {
            return OffsetDateTime.parse(s.strip()).toLocalDate();
        } catch (Exception ignored) {
        }
        try {
            return LocalDate.parse(s.strip().substring(0, 10));
        } catch (Exception ignored) {
        }
        return null;
    }
}
