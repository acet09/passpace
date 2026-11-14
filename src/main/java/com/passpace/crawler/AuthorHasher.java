package com.passpace.crawler;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

/**
 * [용성] "같은 작성자 = 1표본"(기획안 7.1.3)을 지키되 작성자 아이디는 저장하지 않는다(7.1.4).
 * SHA-256(salt + 사이트 + 작성자) 64자만 PASS_REVIEWS.author_hash 에 남긴다.
 * salt 는 application-local.yml 의 passpace.collect.author-salt 에 팀만 아는 값으로 둔다.
 */
@Component
public class AuthorHasher {

    private final String salt;

    public AuthorHasher(@Value("${passpace.collect.author-salt:passpace-default-salt}") String salt) {
        this.salt = salt;
    }

    public String hash(ReviewSite site, String authorKey) {
        if (authorKey == null || authorKey.isBlank()) return null;
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] digest = md.digest((salt + "|" + site.name() + "|" + authorKey.toLowerCase()).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
