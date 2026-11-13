package com.passpace.constant;

/**
 * 사용자 권한. DB users.role 칸에 이름(ADMIN·USER)이 글자로 저장된다.
 * Spring Security 는 권한 이름 앞에 "ROLE_" 이 붙어 있어야 hasRole("ADMIN") 과 비교한다.
 */
public enum Role {
    ADMIN,  // 관리자: 수집 관리 화면(/admin) 사용 (5단계에서 users.role 칸 추가 후 적용)
    USER;   // 일반 사용자: 챗봇·학습계획·마이페이지 (회원가입하면 항상 USER)

    public String role() {
        return "ROLE_" + this.name();
    }
}
