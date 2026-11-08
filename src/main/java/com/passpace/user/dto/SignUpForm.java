package com.passpace.user.dto;

import com.passpace.common.code.MajorType;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * [한결] 회원가입 화면 입력값.
 * 길이 제한은 DB 컬럼 크기에 맞춤 (USERS.login_id 30, nickname 50, email 255)
 */
// TODO(한결): 필드에 검증 어노테이션(jakarta.validation) 추가 - 아이디(영문·숫자·_ 4~20자), 비밀번호(8~50자), 비밀번호 확인, 닉네임(50자 이하), 이메일 형식, 전공 구분 필수
public class SignUpForm {
    @NotBlank(message = "아이디를 입력해 주세요.")
    @Pattern(
            regexp = "^[a-zA-Z0-9_]{4,20}$",
            message = "아이디는 영문, 숫자, 밑줄(_)로 4~20자여야 합니다."
    )
    private String loginId;

    @NotBlank(message = "비밀번호를 입력해 주세요.")
    @Size(min = 8, max = 50, message = "비밀번호는 8~50자여야 합니다.")
    private String password;

    @NotBlank(message = "비밀번호 확인을 입력해 주세요.")
    private String passwordConfirm;

    @NotBlank(message = "닉네임을 입력해 주세요.")
    @Size(max = 50, message = "닉네임은 50자 이하여야 합니다.")
    private String nickname;

    @NotBlank(message = "이메일을 입력해 주세요.")
    @Email(message = "올바른 이메일 형식으로 입력해 주세요.")
    @Size(max = 255, message = "이메일은 255자 이하여야 합니다.")
    private String email;

    @NotNull(message = "전공 구분을 선택해 주세요.")
    private MajorType majorType;

    public String getLoginId() { return loginId; }
    public void setLoginId(String loginId) { this.loginId = loginId; }
    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }
    public String getPasswordConfirm() { return passwordConfirm; }
    public void setPasswordConfirm(String passwordConfirm) { this.passwordConfirm = passwordConfirm; }
    public String getNickname() { return nickname; }
    public void setNickname(String nickname) { this.nickname = nickname; }
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public MajorType getMajorType() { return majorType; }
    public void setMajorType(MajorType majorType) { this.majorType = majorType; }
}
