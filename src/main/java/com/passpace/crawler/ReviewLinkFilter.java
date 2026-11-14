package com.passpace.crawler;

import com.passpace.crawler.ListingParser.ListingLink;

import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * [용성] 목록에서 찾은 링크 중 "수집 대상 자격증의 후기 글"만 남긴다 (기획안 7.1.1).
 *  - 허용 사이트의 개별 글 주소일 것
 *  - 제목(또는 주소)에 자격증 키워드 + 후기 키워드가 함께 있을 것
 *  - 같은 글 중복 제거
 */
public final class ReviewLinkFilter {

    static final Pattern CERT_WORD = Pattern.compile("정보처리기사|정처기|SQLD|sqld|에스큐엘디");
    static final Pattern REVIEW_WORD = Pattern.compile("합격|후기|불합격|떨어|공부\\s*(?:법|방법|기록)|회고");

    /** 필터를 통과한 글 1개 */
    public record Candidate(String url, ReviewSite site, String label, java.time.LocalDate listedDate) {
    }

    private ReviewLinkFilter() {
    }

    public static List<Candidate> filter(List<ListingLink> links) {
        List<Candidate> result = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        for (ListingLink link : links) {
            String url = UrlText.canonical(link.url());
            ReviewSite site = ReviewSite.of(url).orElse(null);
            if (site == null || !site.isPostUrl(url) || !seen.add(url)) continue;
            if (!looksLikeReview(link.label(), url)) continue;
            result.add(new Candidate(url, site, link.label(), link.postedAt()));
        }
        return result;
    }

    static boolean looksLikeReview(String label, String asciiUrl) {
        String text = (label == null ? "" : label) + " " + decode(asciiUrl);
        return CERT_WORD.matcher(text).find() && REVIEW_WORD.matcher(text).find();
    }

    private static String decode(String s) {
        try {
            return URLDecoder.decode(s.replace("+", "%2B"), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException e) {
            return s;
        }
    }
}
