package com.passpace.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Swagger 화면 설정. 오른쪽 위 Authorize 버튼에 토큰을 넣으면 모든 요청에 Bearer 헤더가 붙는다 */
@Configuration
public class SwaggerConfig {

    private static final String SECURITY_SCHEME_NAME = "BearerAuth";

    @Bean
    public OpenAPI openAPI() {
        return new OpenAPI()
                .info(new Info()
                        .title("패스페이스(PASS PACE) API")
                        .version("JWT 1단계")
                        .description("""
                                ## 인증
                                - `POST /auth/login` 으로 받은 `accessToken` 을 오른쪽 위 **Authorize** 에 넣습니다 (Bearer 없이 토큰만).
                                - 토큰 없이 쓸 수 있는 API: `/auth/login`, `/auth/signup`, Swagger

                                ## 공통 응답
                                - 성공: `{"status":"SUCCESS","code":200,"data":...}`
                                - 실패: `{"status":"ERROR","code":401,"data":{"code":"FAILURE_JWT_VERIFIED","ko":"…","en":"…","detail":null}}`
                                """))
                .addSecurityItem(new SecurityRequirement().addList(SECURITY_SCHEME_NAME))
                .components(new Components().addSecuritySchemes(SECURITY_SCHEME_NAME,
                        new SecurityScheme()
                                .name(SECURITY_SCHEME_NAME)
                                .type(SecurityScheme.Type.HTTP)
                                .scheme("bearer")
                                .bearerFormat("JWT")
                                .description("로그인 응답의 accessToken 값")));
    }
}
