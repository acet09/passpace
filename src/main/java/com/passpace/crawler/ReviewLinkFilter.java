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

    static final Pattern CERT_WORD = Pattern.compile("정보처리기사|정처기|SQLD|sqld|에스큐엘디"
            + "|컴퓨터\\s*활용\\s*능력|컴활|(?i:ADsP)|데이터\\s*분석\\s*준\\s*전문가"
            + "|산업\\s*안전\\s*기사|산안기"   // [11-26] 산업안전기사
            + "|빅\\s*데이터\\s*분석\\s*기사|빅분기|전산\\s*회계|전회\\s*[12]");   // [11-26] 빅분기·전산회계
    /** [11-14] 대상이 아닌 비슷한 자격증 (먼저 지운 뒤 CERT_WORD 를 찾는다): 정보처리산업기사·기능사, SQLP, ADP
     *  [11-26] 컴활 2급은 대상이 되어 뺐고, 산업안전산업기사·건설안전기사를 넣었다 */
    static final Pattern OTHER_CERT = Pattern.compile("정보처리\\s*(?:산업기사|기능사)|정처산기|정처기능사"
            + "|산업\\s*안전\\s*산업\\s*기사|건설\\s*안전\\s*기사|(?i:\\bSQLP\\b)|(?i:\\bADP\\b)|데이터\\s*분석\\s*전문가");
    /**
     * [11-16] 컴활 후기는 "3일컷", "독학 일주일", "취득", "따기" 처럼 제목에 합격·후기가 없는 경우가 많아 단어를 넓혔다.
     * 넓혀서 들어온 글도 품질 검사(시간 정보·합격 여부·3년 이내)를 그대로 거치므로 VALID 기준은 바뀌지 않는다.
     */
    static final Pattern REVIEW_WORD = Pattern.compile("합격|후기|불합격|떨어|공부\\s*(?:법|방법|기록|기간)|회고"
            + "|취득|따기|독학|\\d+\\s*(?:일|주)\\s*컷");

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
        return CERT_WORD.matcher(OTHER_CERT.matcher(text).replaceAll(" ")).find() && REVIEW_WORD.matcher(text).find();
    }

    private static String decode(String s) {
        try {
            return URLDecoder.decode(s.replace("+", "%2B"), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException e) {
            return s;
        }
    }
}
