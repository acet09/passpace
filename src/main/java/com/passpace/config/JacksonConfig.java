package com.passpace.config;

import com.fasterxml.jackson.datatype.jsr310.ser.LocalDateTimeSerializer;
import org.springframework.boot.autoconfigure.jackson.Jackson2ObjectMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

/** 응답의 모든 LocalDateTime 을 "2026-11-20 10:00:00" 모양으로 내보낸다 (요청은 2026-11-20T10:00:00 그대로 받음) */
@Configuration
public class JacksonConfig {

    private static final DateTimeFormatter DATE_TIME_FORMAT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    @Bean
    public Jackson2ObjectMapperBuilderCustomizer localDateTimeFormat() {
        return builder -> builder.serializerByType(
                LocalDateTime.class, new LocalDateTimeSerializer(DATE_TIME_FORMAT));
    }
}
