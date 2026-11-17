package com.passpace.service;

import com.passpace.constant.Role;
import com.passpace.dto.auth.FindOneUsersResponseDto;
import com.passpace.dto.auth.LoginUserRequestDto;
import com.passpace.dto.auth.LoginUserResponseDto;
import com.passpace.dto.auth.SignupRequestDto;
import com.passpace.dto.auth.SignupResponseDto;
import com.passpace.dto.user.UserViews.UserAccount;
import com.passpace.error.ErrorCode;
import com.passpace.error.exception.AuthException;
import com.passpace.error.exception.UserException;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.jwt.JwtUtil;
import com.passpace.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;

/**
 * 회원가입 · 로그인(JWT 발급) · 내 정보.  — 강의안 12주차 AuthService 와 같은 모양
 *
 * 로그인 흐름 (강의안 p.32)
 *   ① 아이디로 회원 찾기 → ② BCrypt 로 비밀번호 비교 → ③ 맞으면 JwtUtil 로 토큰 만들기
 *
 * [passpace] 예전 UserServiceImpl 의 회원가입·로그인 코드를 옮겨 왔다.
 *   (이메일 대신 아이디 로그인, 비밀번호 72바이트 제한, 비밀번호 확인 칸은 그대로)
 */
@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)   // 기본은 읽기 전용, 저장하는 메서드에만 @Transactional 을 다시 붙인다
public class AuthService {

    /** BCrypt 는 앞 72바이트까지만 비교한다 → 더 긴 비밀번호는 뒷부분이 무시되므로 처음부터 막는다 */
    private static final int BCRYPT_MAX_BYTES = 72;

    private final UserRepository userRepository;
    private final BCryptPasswordEncoder encoder;   // SecurityConfig 의 @Bean
    private final JwtUtil jwtUtil;

    /** 회원가입: 항상 일반 사용자(USER)로 만든다. 비밀번호는 BCrypt 로 바꿔 저장 */
    @Transactional
    public SignupResponseDto signup(SignupRequestDto request) {
        if (request.password().getBytes(StandardCharsets.UTF_8).length > BCRYPT_MAX_BYTES) {
            throw new UserException(ErrorCode.INVALID_REQUEST,
                    "password: 비밀번호는 72바이트 이하여야 합니다. 한글만 입력하면 최대 24자입니다.");
        }
        if (!request.password().equals(request.passwordConfirm())) {
            throw new UserException(ErrorCode.INVALID_REQUEST, "passwordConfirm: 비밀번호가 일치하지 않습니다.");
        }
        if (userRepository.existsByLoginId(request.loginId())) {
            throw new UserException(ErrorCode.DUPLICATED_LOGIN_ID);
        }
        if (userRepository.existsByEmail(request.email(), null)) {
            throw new UserException(ErrorCode.DUPLICATED_EMAIL);
        }

        Long userId = userRepository.insert(
                request.loginId(),
                encoder.encode(request.password()),
                request.nickname(),
                request.email(),
                request.majorType());
        // role 은 DB 기본값 'USER' 로 들어간다 (db/08_add_user_role.sql) — 회원가입으로 ADMIN 을 만들 수 없다
        return new SignupResponseDto(userId);
    }

    /**
     * 로그인: 아이디로 찾고 → 비밀번호 비교 → 토큰 발급.
     * "아이디가 없음"과 "비밀번호 틀림"을 같은 오류로 응답한다 — 어떤 아이디가 가입돼 있는지 알려 주지 않으려고.
     */
    public LoginUserResponseDto login(LoginUserRequestDto request) {
        UserAccount account = userRepository.findAccountByLoginId(request.loginId()).orElse(null);
        if (account == null || !encoder.matches(request.password(), account.passwordHash())) {
            throw new AuthException(ErrorCode.FAILURE_LOGIN);
        }
        log.info("로그인 | userId={}, role={}", account.userId(), account.role());
        return createToken(account);
    }

    /**
     * 토큰 다시 만들기. 마이페이지에서 닉네임·전공을 바꾸면 토큰 안의 값도 바뀌어야 해서 쓴다.
     * (토큰은 한 번 만들면 내용을 고칠 수 없다 → 새로 발급)
     */
    public LoginUserResponseDto reissueToken(Long userId) {
        UserAccount account = userRepository.findAccountByUserId(userId)
                .orElseThrow(() -> new UserException(ErrorCode.NOT_FOUND_USER));
        return createToken(account);
    }

    /** 내 정보: 토큰의 userId 로 DB 에서 다시 읽는다 (role 은 토큰 값 사용) */
    public FindOneUsersResponseDto findOneUser(JwtPrincipal loginUser) {
        return userRepository.findProfile(loginUser.getUserId())
                .map(profile -> new FindOneUsersResponseDto(profile, loginUser.getRole()))
                .orElseThrow(() -> new UserException(ErrorCode.NOT_FOUND_USER));
    }

    private LoginUserResponseDto createToken(UserAccount account) {
        // role 칸이 비어 있으면(예전 DB) 일반 사용자로 본다
        String role = account.role() == null ? Role.USER.name() : account.role();
        JwtPrincipal principal = new JwtPrincipal(
                account.userId(), account.loginId(), account.nickname(), account.majorType(), role);
        return new LoginUserResponseDto(jwtUtil.createToken(principal), jwtUtil.getAccessTokenValidityInSeconds());
    }
}
