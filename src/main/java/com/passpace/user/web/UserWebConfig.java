package com.passpace.user.web;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/** [한결] 로그인 확인 인터셉터 등록 */
@Configuration
public class UserWebConfig implements WebMvcConfigurer {

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        // TODO(한결): 구현
        registry.addInterceptor(new LoginCheckInterceptor())
                .addPathPatterns("/mypage", "/mypage/**");
    }
}
