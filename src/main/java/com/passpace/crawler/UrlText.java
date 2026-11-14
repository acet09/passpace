package com.passpace.crawler;

import java.nio.charset.StandardCharsets;

/** [용성] 한글이 섞인 주소를 %XX 로 바꾸고, 비교용으로 query·fragment·끝 슬래시를 정리한다 */
public final class UrlText {

    private UrlText() {
    }

    /** 이미 %XX 로 된 부분은 그대로 두고 ASCII 가 아닌 글자와 공백만 인코딩 */
    public static String toAscii(String url) {
        if (url == null) return null;
        StringBuilder sb = new StringBuilder();
        url.strip().codePoints().forEach(cp -> {
            if (cp > 127 || cp == ' ') {
                for (byte b : new String(Character.toChars(cp)).getBytes(StandardCharsets.UTF_8)) {
                    sb.append('%').append(String.format("%02X", b & 0xff));
                }
            } else {
                sb.appendCodePoint(cp);
            }
        });
        return sb.toString();
    }

    /** 같은 글을 한 번만 저장하도록: http→https, query·fragment 제거, 끝 슬래시 제거 */
    public static String canonical(String url) {
        String s = toAscii(url);
        String dc = dcinsidePost(s);
        if (dc != null) return dc;
        int cut = s.length();
        for (char c : new char[]{'?', '#'}) {
            int i = s.indexOf(c);
            if (i >= 0 && i < cut) cut = i;
        }
        s = s.substring(0, cut);
        if (s.startsWith("http://")) s = "https://" + s.substring(7);
        while (s.endsWith("/") && s.indexOf('/', 8) < s.length() - 1) s = s.substring(0, s.length() - 1);
        return s;
    }

    private static final java.util.regex.Pattern DC_VIEW = java.util.regex.Pattern.compile(
            "^https?://gall\\.dcinside\\.com/mini/board/view/?\\?(.*)$");
    private static final java.util.regex.Pattern DC_ID = java.util.regex.Pattern.compile("(?:^|&)id=([A-Za-z0-9_]+)");
    private static final java.util.regex.Pattern DC_NO = java.util.regex.Pattern.compile("(?:^|&)no=(\\d+)");

    /**
     * [11-14] 디시인사이드 글은 주소의 query(id·no)가 글을 구분하므로 지우면 안 된다.
     * page·search 같은 나머지 query 만 지우고 "…/view/?id=갤러리&no=번호" 한 모양으로 맞춘다. 디시 글 주소가 아니면 null
     */
    static String dcinsidePost(String ascii) {
        if (ascii == null) return null;
        java.util.regex.Matcher m = DC_VIEW.matcher(ascii.split("#", 2)[0]);
        if (!m.matches()) return null;
        java.util.regex.Matcher id = DC_ID.matcher(m.group(1));
        java.util.regex.Matcher no = DC_NO.matcher(m.group(1));
        if (!id.find() || !no.find()) return null;
        return "https://gall.dcinside.com/mini/board/view/?id=" + id.group(1) + "&no=" + no.group(1);
    }
}
