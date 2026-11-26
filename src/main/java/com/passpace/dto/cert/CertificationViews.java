package com.passpace.dto.cert;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

/**
 * [11-26] 지원 자격증 정보 메뉴 응답 모양 (GET /api/certifications, /api/certifications/{id}).
 * 값이 없으면 null 로 보낸다. 앱은 null 항목을 숨기거나 "공식 사이트에서 확인" 으로 보여 준다 (값을 지어내지 않는다).
 */
public final class CertificationViews {

    private CertificationViews() {
    }

    /** 목록 한 줄 */
    public record CertSummary(long certificationId, String name, String certType, String grade, String category,
                              String issuingOrg, String summary, List<String> examTypes, boolean alwaysOpen,
                              NextEvent nextEvent) {
    }

    /** 가장 가까운 앞으로의 일정 1개. kind: REG_START(접수 시작) / REG_OPEN(접수 중, date=마감일) / ADD_REG(추가 접수) / EXAM(시험) / RESULT(발표) */
    public record NextEvent(String kind, String label, LocalDate date, long dDay, String examType, Integer examYear,
                            Integer roundNo, boolean projected) {
    }

    /** 상세 */
    public record CertDetail(CertSummary basic, String eligibility, String eligibilityCheckUrl, String officialUrl,
                             String applyUrl, LocalDate infoVerifiedAt, Notes notes, List<ExamInfo> exams,
                             Round nextExam, List<Round> schedule, List<PassRate> passRates) {
    }

    /** 알아두면 좋은 정보 */
    public record Notes(String writtenExemption, String requiredItems, String validity, String refundNote,
                        String refundUrl, String resultNotice, String relatedCerts) {
    }

    /** 시험 구분별 정보 (필기 / 실기) */
    public record ExamInfo(String examType, String examTypeLabel, Integer fee, Integer questionCount,
                           Integer durationMinutes, String method, String passCriteria, Integer scopeYear,
                           List<String> subjects) {
    }

    /** 회차 일정 한 줄 */
    public record Round(Integer examYear, Integer roundNo, String examType, String examTypeLabel,
                        LocalDateTime regStartAt, LocalDateTime regEndAt, LocalDateTime addRegStartAt,
                        LocalDateTime addRegEndAt, LocalDate examStartDate, LocalDate examEndDate,
                        LocalDate resultDate, boolean past, boolean projected) {
    }

    /** 합격률 (EXAM_ROUNDS 에 값이 있는 회차만) */
    public record PassRate(Integer examYear, Integer roundNo, String examTypeLabel, Integer applicantCount,
                           Integer passCount, Double passRate) {
    }
}
