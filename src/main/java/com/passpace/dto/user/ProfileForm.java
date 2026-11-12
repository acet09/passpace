package com.passpace.dto.user;

import com.passpace.constant.MajorType;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/** [한결] 마이페이지 - 회원정보 수정 입력값 (아이디·비밀번호는 이번 범위에서 수정 안 함) */
// TODO(한결): 필드에 검증 어노테이션(jakarta.validation) 추가 - 닉네임 필수(50자 이하), 이메일 형식, 전공 구분 필수
public class ProfileForm {

    @NotBlank(message = "닉네임을 입력해 주세요.")
    @Size(max = 50, message = "닉네임은 50자 이하여야 합니다.")
    private String nickname;

    @NotBlank(message = "이메일을 입력해 주세요.")
    @Email(message = "올바른 이메일 형식으로 입력해 주세요.")
    @Size(max = 255, message = "이메일은 255자 이하여야 합니다.")
    private String email;

    @NotNull(message = "전공 구분을 선택해 주세요.")
    private MajorType majorType;

    public String getNickname() { return nickname; }
    public void setNickname(String nickname) { this.nickname = nickname; }
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public MajorType getMajorType() { return majorType; }
    public void setMajorType(MajorType majorType) { this.majorType = majorType; }
}
