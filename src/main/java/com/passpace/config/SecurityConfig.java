package com.passpace.config;

import com.passpace.jwt.JwtAccessDeniedHandler;
import com.passpace.jwt.JwtAuthenticationEntryPoint;
import com.passpace.jwt.JwtSecurityConfig;
import com.passpace.jwt.JwtUtil;
import com.passpace.jwt.SecurityPaths;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.List;

/**
 * 보안 설정 한 곳. "누가 어떤 주소에 들어올 수 있나"를 여기서 정한다.
 */
@Configuration
@EnableWebSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtUtil jwtUtil;
    private final JwtAuthenticationEntryPoint jwtAuthenticationEntryPoint;
    private final JwtAccessDeniedHandler jwtAccessDeniedHandler;

    /** 비밀번호는 BCrypt 로 한 방향 암호화해서 저장한다 (원래 비밀번호로 되돌릴 수 없음) */
    @Bean
    public BCryptPasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                // 토큰 방식이라 쿠키 기반 공격(CSRF) 방어가 필요 없다
                .csrf(csrf -> csrf.disable())
                // 다른 주소(웹 화면)에서 부르는 것 허락 — 아래 corsConfigurationSource 사용
                .cors(Customizer.withDefaults())
                // 서버가 로그인 상태를 기억하지 않는다 (세션 없음). 요청마다 토큰으로 확인
                // [passpace] 예전 세션 코드(SessionConst·LoginCheckInterceptor·AdminAuthInterceptor)는 모두 지웠다.
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                // [passpace] Security 기본 로그아웃(POST /logout 처리)을 끈다.
                //   토큰 방식은 "화면(앱)이 저장한 토큰을 지우면 로그아웃"이라 서버가 할 일이 없다 (auth.js 의 logout)
                .logout(logout -> logout.disable())
                // 401·403 도 우리 JSON 모양으로
                .exceptionHandling(e -> e
                        .authenticationEntryPoint(jwtAuthenticationEntryPoint)
                        .accessDeniedHandler(jwtAccessDeniedHandler))
                // 주소별 권한 규칙 — 위에서부터 먼저 맞는 규칙 하나만 적용된다
                .authorizeHttpRequests(auth -> auth
                        // ① 토큰 없이 들어오는 주소 (로그인·회원가입·Swagger·화면 껍데기)
                        //    목록은 jwt/SecurityPaths 한 곳에서만 고친다
                        .requestMatchers(SecurityPaths.PUBLIC).permitAll()
                        // ② [용성] 관리자 수집 API — ADMIN 토큰만 (USER 토큰이면 403)
                        //    화면 껍데기 GET /admin/collect 는 ①에서 이미 열렸으므로 여기에 걸리지 않는다
                        .requestMatchers("/admin/**").hasRole("ADMIN")
                        // ③ 나머지(챗봇 /api/chat/**, 마이페이지 /users/me/**, /auth/user-info)는 로그인한 사람(토큰 있음)만
                        //    "본인 대화방인가" 같은 검사는 주소로 알 수 없어서 Service·Controller 에서 DB 를 보고 한다
                        .anyRequest().authenticated())
                // JwtExceptionHandlerFilter · JwtFilter 끼워 넣기
                .with(new JwtSecurityConfig(jwtUtil), Customizer.withDefaults());

        return http.build();
    }

    /** 웹 화면(로컬 개발 주소)에서 이 API 를 부를 수 있게 허락 */
    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();
        configuration.setAllowedOriginPatterns(
                List.of("http://localhost:[*]", "http://127.0.0.1:[*]"));
        configuration.addAllowedHeader("*");
        configuration.setAllowedMethods(
                List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        configuration.setAllowCredentials(false);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", configuration);
        return source;
    }
}
