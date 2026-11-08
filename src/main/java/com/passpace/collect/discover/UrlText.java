package com.passpace.collect.discover;

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
}
