package com.passpace.jwt;

import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.GrantedAuthority;

import java.util.Collection;

/** Spring Security 가 "로그인된 사람"으로 인정하는 객체. principal 자리에 JwtPrincipal 을 넣는다 */
public class UserAuthentication extends UsernamePasswordAuthenticationToken {
    public UserAuthentication(Object principal, Object credentials, Collection<? extends GrantedAuthority> authorities) {
        super(principal, credentials, authorities);
    }
}
