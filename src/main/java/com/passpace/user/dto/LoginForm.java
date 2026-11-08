package com.passpace.user.dto;

import jakarta.validation.constraints.NotBlank;
/** [한결] 로그인 화면 입력값 */
// TODO(한결): 필드에 검증 어노테이션(jakarta.validation) 추가 - 아이디·비밀번호 필수
public class LoginForm {

    @NotBlank(message = "아이디를 입력해 주세요.")
    private String loginId;

    @NotBlank(message = "비밀번호를 입력해 주세요.")
    private String password;

    public String getLoginId() { return loginId; }
    public void setLoginId(String loginId) { this.loginId = loginId; }
    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }
}
