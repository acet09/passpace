package com.passpace.dto.auth;

import com.passpace.constant.MajorType;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * 회원가입 요청 (POST /auth/signup 의 본문 JSON).
 * Controller 파라미터에 @Valid 가 붙어 있어서, 아래 규칙을 어기면 Service 까지 가지 않고 400 INVALID_REQUEST.
 * 길이 제한은 DB 칸 크기에 맞춘 값 (USERS.login_id 30, nickname 50, email 255) — 예전 SignUpForm 규칙 그대로.
 *
 * 예) {"loginId":"kim_01","password":"pass1234","passwordConfirm":"pass1234",
 *      "nickname":"김패스","email":"kim@example.com","majorType":"MAJOR"}
 */
public record SignupRequestDto(
        @NotBlank(message = "아이디를 입력해 주세요.")
        @Pattern(regexp = "^[a-zA-Z0-9_]{4,20}$", message = "아이디는 영문, 숫자, 밑줄(_)로 4~20자여야 합니다.")
        String loginId,

        @NotBlank(message = "비밀번호를 입력해 주세요.")
        @Size(min = 8, max = 50, message = "비밀번호는 8~50자여야 합니다.")
        String password,

        @NotBlank(message = "비밀번호 확인을 입력해 주세요.")
        String passwordConfirm,

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
