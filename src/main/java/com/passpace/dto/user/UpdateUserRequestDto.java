package com.passpace.dto.user;

import com.passpace.constant.MajorType;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * 회원정보 수정 요청 (PUT /users/me). 아이디·비밀번호는 이번 범위에서 수정하지 않는다.
 * (예전 ProfileForm 규칙 그대로)
 */
public record UpdateUserRequestDto(
        @NotBlank(message = "닉네임을 입력해 주세요.")
        @Size(max = 50, message = "닉네임은 50자 이하여야 합니다.")
        String nickname,

        @NotBlank(message = "이메일을 입력해 주세요.")
        @Email(message = "올바른 이메일 형식으로 입력해 주세요.")
        @Size(max = 255, message = "이메일은 255자 이하여야 합니다.")
        String email,

        @NotNull(message = "전공 구분을 선택해 주세요.")
        MajorType majorType
) {}
