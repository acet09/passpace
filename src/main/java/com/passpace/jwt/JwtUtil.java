package com.passpace.jwt;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import com.passpace.constant.MajorType;
import com.passpace.constant.Role;
import com.passpace.error.ErrorCode;
import com.passpace.error.exception.JwtException;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.util.Date;
import java.util.List;

/**
 * JWT 만들기(로그인할 때)와 검증하기(요청마다).
 *
 * 토큰 = 헤더.내용(claims).서명
 *  - 내용: userId, loginId, nickname, majorType, role, 만료 시각 ... (누구나 Base64 로 풀어 볼 수 있다 → 비밀번호는 절대 넣지 않는다)
 *  - 서명: 서버만 아는 secret 으로 만든다 → 내용을 한 글자라도 바꾸면 서명이 맞지 않아 거절된다
 */
@Component
public class JwtUtil implements InitializingBean {

    @Value("${jwt.issuer}")
    private String issuer;
    @Value("${jwt.secret}")
    private String secret;
    @Value("${jwt.access-token-validity-in-seconds}")
    private long accessTokenValidityInSeconds;

    private SecretKey key;

    /** 스프링이 @Value 를 다 채운 뒤 한 번 불러 준다 → 글자 secret 을 서명용 열쇠로 바꿔 둔다 */
    @Override
    public void afterPropertiesSet() {
        key = Keys.hmacShaKeyFor(Decoders.BASE64.decode(secret));
    }

    public long getAccessTokenValidityInSeconds() {
        return accessTokenValidityInSeconds;
    }

    /** 로그인 성공 시 access token 발급 */
    public String createToken(JwtPrincipal principal) {
        Date now = new Date();
        Date exp = new Date(now.getTime() + accessTokenValidityInSeconds * 1000);
        return Jwts.builder()
                .subject(String.valueOf(principal.getUserId()))
                .issuer(issuer)
                .claim("userId", principal.getUserId())
                .claim("loginId", principal.getLoginId())
                .claim("nickname", principal.getNickname())
                .claim("majorType", principal.getMajorType() == null ? null : principal.getMajorType().name())
                .claim("role", principal.getRole())
                .issuedAt(now)
                .expiration(exp)
                .signWith(key)            // HS256 (secret 길이에 맞춰 자동 선택)
                .compact();
    }

    /** 서명·만료를 검사하고 내용(claims)을 돌려준다. 문제가 있으면 우리 JwtException(401) */
    public Claims validateToken(String token) {
        try {
            return Jwts.parser().verifyWith(key).build()
                    .parseSignedClaims(token).getPayload();   // 서명·만료를 한 번에 확인
        } catch (ExpiredJwtException e) {
            throw new JwtException(ErrorCode.JWT_EXPIRED);
        } catch (io.jsonwebtoken.JwtException | IllegalArgumentException e) {
            // 서명 불일치, 모양이 깨진 토큰, 지원하지 않는 토큰 등
            throw new JwtException(ErrorCode.INVALID_JWT);
        }
    }

    /** 검증된 claims 로 Spring Security 의 인증 객체를 만든다 (DB 조회 없음) */
    public Authentication getAuthentication(Claims claims, String token) {
        Long userId = claims.get("userId", Long.class);
        String loginId = claims.get("loginId", String.class);
        String nickname = claims.get("nickname", String.class);
        String major = claims.get("majorType", String.class);
        String role = claims.get("role", String.class);

        JwtPrincipal principal = new JwtPrincipal(userId, loginId, nickname,
                major == null ? null : MajorType.valueOf(major), role);
        List<SimpleGrantedAuthority> authorities = List.of(new SimpleGrantedAuthority(Role.valueOf(role).role()));
        return new UserAuthentication(principal, token, authorities);
    }
}
