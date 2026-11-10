package com.passpace.collect.web;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/** [용성] 관리자 잠금 인터셉터 등록 (한결 UserWebConfig 와 별도 파일, 서로 영향 없음) */
@Configuration
public class AdminWebConfig implements WebMvcConfigurer {

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(new AdminAuthInterceptor())
                .addPathPatterns("/admin", "/admin/**")
                .excludePathPatterns("/admin/login");
    }
}
