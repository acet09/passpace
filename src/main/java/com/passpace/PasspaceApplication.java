package com.passpace;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * 패스페이스(PASS PACE) 정보처리기사 실험판 - 실행 시작점.
 *
 * 패키지(담당) 구성
 *  - common  : 세 영역이 함께 쓰는 계약(DTO·인터페이스·코드값). 혼자 수정 금지
 *  - global  : 공통 예외 처리
 *  - user    : [한결] 웹페이지 4개(메인·로그인·회원가입·마이페이지)와 회원
 *  - collect : [용성] 정보처리기사 시험정보 API 수집, 합격 후기 크롤링
 *  - chat    : [동건] 로컬 LLM(Ollama) 챗봇
 *
 * 세 영역은 서로의 클래스를 직접 import 하지 않는다.
 * 연결은 ① DB 테이블 ② common 패키지 ③ 화면 fragment(챗봇 위젯) 세 가지로만 한다.
 */
@SpringBootApplication
public class PasspaceApplication {

    public static void main(String[] args) {
        SpringApplication.run(PasspaceApplication.class, args);
    }
}
