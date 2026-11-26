package com.passpace.repository;

import com.passpace.dto.cert.CertificationViews.PassRate;
import com.passpace.dto.cert.CertificationViews.Round;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/** [11-26] 지원 자격증 정보 메뉴용 조회 (읽기 전용) */
public interface CertificationInfoQuery {

    /** CERTIFICATIONS + CERTIFICATION_INFO 한 행 (정보 행이 없으면 정보 칸은 null) */
    record CertRow(long certificationId, String name, String certType, String issuingOrg, String passCriteria,
                   String grade, String category, String summary, String eligibility, String eligibilityCheckUrl,
                   boolean alwaysOpen, String writtenExemption, String requiredItems, String validity,
                   String refundNote, String refundUrl, String resultNotice, String relatedCerts,
                   String officialUrl, String applyUrl, LocalDate infoVerifiedAt) {
    }

    /** CERTIFICATION_EXAM_INFO 한 행 */
    record ExamInfoRow(String examType, Integer fee, Integer questionCount, Integer durationMinutes,
                       String method, String passCriteria, Integer scopeYear) {
    }

    /** active_yn = 'Y' 인 자격증 전체 (certification_id 순) */
    List<CertRow> findActive();

    Optional<CertRow> findActive(long certificationId);

    List<ExamInfoRow> findExamInfos(long certificationId);

    /** 시험 구분(WRITTEN/PRACTICAL) → 과목명 (display_order 순) */
    Map<String, List<String>> findSubjects(long certificationId);

    /** 시험 구분 목록 (과목·회차·시험 정보 중 하나라도 있는 구분) */
    Map<Long, List<String>> findExamTypes();

    /** fromYear 이후 회차 전체 (연도·회차·구분 순). past 는 today 기준으로 채운다 */
    List<Round> findRounds(long certificationId, int fromYear, LocalDate today);

    /** fromYear 이후 회차 전체 (모든 자격증) → 목록의 다음 일정 계산용 */
    Map<Long, List<Round>> findRoundsAll(int fromYear, LocalDate today);

    /** 합격률이 있는 최근 회차 (최신순, limit 개) */
    List<PassRate> findPassRates(long certificationId, int limit);
}
