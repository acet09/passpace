package com.passpace.dto.auth;

import com.passpace.constant.MajorType;
import com.passpace.dto.user.UserViews.UserProfile;
import lombok.Getter;

import java.time.LocalDateTime;

/**
 * 내 정보 응답 (GET /auth/user-info).
 * DB 의 행(비밀번호 해시 포함)을 그대로 내보내지 않는다 — 필요한 칸만 골라 담는다.
 */
@Getter
public class FindOneUsersResponseDto {
    private final Long userId;
    private final String loginId;
    private final String nickname;
    private final String email;
    private final MajorType majorType;     // 예: "MAJOR"
    private final String majorTypeLabel;   // 화면 표시용 한글 (예: "전공")
    private final String role;             // "ADMIN" 또는 "USER"
    private final LocalDateTime createdAt; // 응답에서는 "2026-11-12 10:00:00" 모양 (JacksonConfig)

    public FindOneUsersResponseDto(UserProfile profile, String role) {
        this.userId = profile.userId();
        this.loginId = profile.loginId();
        this.nickname = profile.nickname();
        this.email = profile.email();
        this.majorType = profile.majorType();
        this.majorTypeLabel = profile.majorType() == null ? null : profile.majorType().getLabel();
        this.role = role;
        this.createdAt = profile.createdAt();
    }
}
