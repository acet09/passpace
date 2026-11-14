package com.passpace.crawler;

import java.net.URI;
import java.util.Optional;
import java.util.regex.Pattern;

/**
 * [용성] 수집을 허용한 블로그 플랫폼 (기획안 7.1.1 · 사용자 결정: velog + 티스토리).
 * 여기에 없는 호스트는 탐색·수집하지 않는다.
 *
 * providerName 은 DATA_SOURCES.provider_name 과 같아야 한다 → 그 행의 permission_checked_at 이
 * 비어 있으면(약관·robots·AI 활용 확인 전) 수집하지 않는다.
 */
public enum ReviewSite {

    /** 글 주소: https://velog.io/@아이디/글주소 */
    VELOG("velog", Pattern.compile("^https://velog\\.io/@[^/?#]+/[^/?#]+$")),
    /** 글 주소: https://블로그.tistory.com/123 또는 /entry/제목 (관리·검색·카테고리 페이지 제외) */
    TISTORY("tistory", Pattern.compile("^https://[a-z0-9-]+\\.tistory\\.com/(?:\\d+|entry/[^?#]+)$")),
    /**
     * [11-14] 디시인사이드 마이너 갤러리 글: https://gall.dcinside.com/mini/board/view/?id=갤러리&no=번호
     * (UrlText.canonical 이 id·no 만 남긴 모양). DATA_SOURCES 행이 없어 source_id 는 NULL 로 저장한다.
     */
    DCINSIDE("dcinside", Pattern.compile("^https://gall\\.dcinside\\.com/mini/board/view/\\?id=[A-Za-z0-9_]+&no=\\d+$"));

    private final String providerName;
    private final Pattern postUrl;

    ReviewSite(String providerName, Pattern postUrl) {
        this.providerName = providerName;
        this.postUrl = postUrl;
    }

    public String providerName() {
        return providerName;
    }

    /** 목록·피드 주소도 포함해 어느 사이트인지 (v2.velog.io 는 velog RSS 주소) */
    public static Optional<ReviewSite> of(String url) {
        String host;
        try {
            host = URI.create(UrlText.toAscii(url)).getHost();
        } catch (IllegalArgumentException e) {
            return Optional.empty();
        }
        if (host == null) return Optional.empty();
        host = host.toLowerCase();
        if (host.equals("velog.io") || host.equals("v2.velog.io")) return Optional.of(VELOG);
        if (host.endsWith(".tistory.com") && !host.equals("www.tistory.com")) return Optional.of(TISTORY);
        if (host.equals("gall.dcinside.com")) return Optional.of(DCINSIDE);
        return Optional.empty();
    }

    /** 개별 글 주소인지 (목록·태그·검색·관리 페이지가 아님) */
    public boolean isPostUrl(String asciiUrl) {
        return postUrl.matcher(asciiUrl).matches();
    }

    /**
     * 작성자 구분값 (해시 전 원본, 저장하지 않음)
     *  velog   → 주소의 @아이디
     *  tistory → 블로그 하위도메인
     *  dcinside → 주소에 작성자가 없어 null (글 페이지에서 DcinsideParser 가 뽑는다)
     */
    public String authorKey(String asciiUrl) {
        if (this == DCINSIDE) return null;
        URI uri = URI.create(asciiUrl);
        if (this == VELOG) {
            String[] parts = uri.getRawPath().split("/");
            return parts.length > 1 ? parts[1].toLowerCase() : null;
        }
        String host = uri.getHost().toLowerCase();
        return host.substring(0, host.indexOf('.'));
    }
}
