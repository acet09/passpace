package com.passpace.crawler;

import com.passpace.crawler.ListingParser.ListingLink;
import com.passpace.crawler.PostPageParser.PostPage;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [용성·11-14] 디시인사이드 마이너 갤러리(정보처리 미니갤 등) 목록·글 파서. 네트워크 없이 테스트 가능.
 *
 * 2026-11-14 확인한 화면 구조 기준 (자바스크립트 없이 HTML 에 목록·본문이 있음)
 *  - 목록: tr.ub-content → td.gall_tit a(글 주소·제목), td.gall_date[title="2026-11-10 12:34:56"]
 *  - 글:   span.title_subject(제목), div.write_div(본문), span.gall_date[title](작성일),
 *          div.gall_writer[data-nick, data-uid, data-ip](작성자)
 * ※ 실제 페이지로 fixture 를 만들어 선택자를 다시 확인할 것 (사이트 개편 시 바뀔 수 있음)
 */
public final class DcinsideParser {

    private static final Pattern DATE = Pattern.compile("(20\\d{2})[.\\-/](\\d{1,2})[.\\-/](\\d{1,2})");

    private DcinsideParser() {
    }

    /** 목록 페이지 → 글 링크(공지 제외). 구조가 달라 한 줄도 못 찾으면 일반 HTML 링크 추출로 대신한다 */
    public static List<ListingLink> listing(String html, String baseUrl) {
        Document doc = Jsoup.parse(html == null ? "" : html, baseUrl);
        List<ListingLink> links = new ArrayList<>();
        for (Element row : doc.select("tr.ub-content")) {
            if ("icon_notice".equals(row.attr("data-type"))) continue;
            Element num = row.selectFirst("td.gall_num");
            if (num != null && !num.text().strip().matches("\\d+")) continue;      // 공지·설문·AD
            Element a = row.selectFirst("td.gall_tit a[href*=/board/view]");
            if (a == null) continue;
            String url = UrlText.canonical(a.absUrl("href"));
            if (!ReviewSite.DCINSIDE.isPostUrl(url)) continue;
            Element date = row.selectFirst("td.gall_date");
            links.add(new ListingLink(url, a.text().strip(), date == null ? null : toDate(date.attr("title"), date.text())));
        }
        return links.isEmpty() ? ListingParser.parseHtml(html == null ? "" : html, baseUrl) : links;
    }

    /** 글 페이지 → 제목·본문·작성일·전재 금지 (본문은 메모리에서만 쓴다) */
    public static PostPage post(Document original, int maxChars) {
        Document doc = original.clone();
        Element subject = doc.selectFirst("span.title_subject");
        String title = subject != null ? subject.text().strip() : doc.title();
        Element dateEl = doc.selectFirst(".gall_writer span.gall_date, span.gall_date");
        LocalDate postedAt = dateEl == null ? null : toDate(dateEl.attr("title"), dateEl.text());
        boolean noReprint = PostPageParser.NO_REPRINT.matcher(doc.body() == null ? "" : doc.body().text()).find();
        Element body = doc.selectFirst("div.write_div");
        String text = body == null ? "" : body.text();
        if (text.length() > maxChars) text = text.substring(0, maxChars);
        return new PostPage(title, text, postedAt, noReprint);
    }

    /**
     * 작성자 구분값 (해시 전 원본, 저장하지 않음)
     *  고정닉(data-uid 있음) → "uid:" + 갤로그 아이디
     *  유동닉(data-uid 없음) → "ip:" + 닉네임 + "|" + IP 앞 두 자리 (예: ㅇㅇ|118.235)
     */
    public static String authorKey(Document doc) {
        Element w = doc.selectFirst("div.gall_writer");
        if (w == null) return null;
        String uid = w.attr("data-uid").strip();
        if (!uid.isEmpty()) return "uid:" + uid;
        String nick = w.attr("data-nick").strip();
        String ip = w.attr("data-ip").strip();
        if (ip.isEmpty()) {
            Element ipEl = w.selectFirst("span.ip");
            if (ipEl != null) ip = ipEl.text().replaceAll("[()\\s]", "");
        }
        if (nick.isEmpty() && ip.isEmpty()) return null;
        return "ip:" + nick + "|" + ip;
    }

    /** title 속성(2026-11-10 12:34:56) 우선, 없으면 글자(2026.11.10 12:34:56). 연도가 없으면(오늘 글 "12:34") null */
    static LocalDate toDate(String titleAttr, String text) {
        for (String s : new String[]{titleAttr, text}) {
            if (s == null) continue;
            Matcher m = DATE.matcher(s);
            if (m.find()) {
                try {
                    return LocalDate.of(Integer.parseInt(m.group(1)), Integer.parseInt(m.group(2)), Integer.parseInt(m.group(3)));
                } catch (Exception ignored) {
                    return null;
                }
            }
        }
        return null;
    }
}
