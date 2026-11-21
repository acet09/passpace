package com.passpace.dto.user;

import com.passpace.constant.MajorType;

import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * [한결] 화면·서비스 사이에서 주고받는 읽기 전용 값들 (record 모음).
 * 파일 하나에 모아 둔 것은 학습용으로 보기 편하게 하기 위함이다.
 */
public final class UserViews {

    private UserViews() {
    }

    /**
     * 로그인 확인용 계정 정보 (비밀번호 해시 포함 → 응답으로 내보내지 않는다)
     * role: "ADMIN" 또는 "USER" (db/08_add_user_role.sql) → 로그인할 때 토큰에 담는다
     */
    public record UserAccount(Long userId, String loginId, String passwordHash, String nickname, MajorType majorType,
                              String role) {
    }

    /** 마이페이지 표시용 회원 정보 */
    public record UserProfile(Long userId, String loginId, String nickname, String email,
                              MajorType majorType, LocalDateTime createdAt) {
    }

    /** 메인 페이지 시험 일정 카드 */
    public record UpcomingExam(int examYear, int roundNo, String examTypeLabel,
                               LocalDateTime regStartAt, LocalDateTime regEndAt,
                               LocalDate examStartDate, LocalDate examEndDate, LocalDate resultDate,
                               long daysLeft, boolean sample) {
    }

    /** 목표 회차 선택 상자 */
    public record ExamRoundOption(Long examRoundId, String label, LocalDate examStartDate) {
    }

    /** 과목별 이해도 입력 줄 */
    public record SubjectOption(Long subjectId, String subjectName) {
    }

    /** 저장되어 있는 활성 목표 */
    public record ActiveGoal(Long goalId, Long examRoundId, LocalDate targetExamDate, Integer dailyMinutes) {
    }
}
