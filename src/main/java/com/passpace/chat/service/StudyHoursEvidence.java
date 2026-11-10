package com.passpace.chat.service;

import java.util.ArrayList;
import java.util.List;

/**
 * [동건] 과목별 학습시간에 관한 공개 학습일지 기반의 잠정 기준값.
 *
 * 중요: 이 클래스가 제공하는 hours는 과목별 실측 '평균'이 아니다.
 * 특정 합격자의 과목별로 식별 가능한 공부시간 + 그 작성자의 공통 공부시간을
 * 식별 가능한 시간의 비율로 배분한 '한 사례 기반 미리보기 추정치'다.
 * 기존 2026 정보처리기사 5과목을 2027 4과목으로 대응한 것은 더 큰 불확실성을 갖는다.
 * 현재 과목별 50명 이상 합격자 표본을 확보하지 못했으므로 대표 평균으로 표시하면 안 된다.
 *
 * 외부 데이터 수집 담당의 DB/API를 임의 변경하지 않고 챗봇 데모에서만 이용한다.
 */
public final class StudyHoursEvidence {
    private StudyHoursEvidence() { }

    public record Observation(String title, int year, double totalHours,
                              String calculation, boolean estimated, String url,
                              boolean usedForBaseline) { }

    public record SubjectEstimate(String name, double hours,
                                  double directlyRecordedHours, int directAuthorCount,
                                  int matchingSyllabusAuthors, String referenceType,
                                  String derivation) { }

    public record CertificateEstimate(String version, String method, String warning,
                                      double referenceTotalHours,
                                      int baselineAuthors, int matchingSyllabusAuthors,
                                      String status,
                                      List<Observation> observations,
                                      List<SubjectEstimate> subjects) {
        /** 이 값은 근거 링크 개수이지 과목별 통계 표본 수와 같지 않다. */
        public int sourceCount() { return observations.size(); }
    }

    private static final String IP_LOG_URL =
            "https://hwankr.tistory.com/entry/정보처리기사-필기-후기";
    private static final String SQLD_LOG_URL = "https://letsgomin.com/2727/";
    private static final String SQLD_EXTRA_URL = "https://bedenblog.tistory.com/273";
    private static final String IP_PRACTICAL_URL = "https://kicdor.tistory.com/63";

    /**
     * 2026 합격자의 5과목별 단독 학습 기록: 226,242,240,117,181분.
     * 추가 공통 기출·오답 430분. 총 1,436분 (23시간56분).
     *
     * 2027년 '소프트웨어 개발'은 구 소프트웨어 설계+개발이 부분 통합된 것으로
     * 추정용 468분을 대응한다. 일부 범위 이동/삭제를 반영하지 못한다.
     * 신 출제기준의 직접 측정 합격자는 0명이다.
     */
    public static CertificateEstimate informationProcessingWritten2027() {
        List<String> names = List.of("소프트웨어 개발", "데이터베이스 구축",
                "프로그래밍 언어 활용", "정보시스템 구축관리");
        int[] directlyIdentifiedMinutes = {226 + 242, 240, 117, 181};
        List<SubjectEstimate> subjects = proportionalCaseEstimate(names,
                directlyIdentifiedMinutes, 430, 1, 0,
                "2026년 구 5과목 1명의 과목별 기록을 2027년 4과목에 임시 대응",
                "공통 기출 430분은 직접 계측한 과목별 시간이 아니며, 식별된 과목 시간 비율로 배분. " +
                "구 소프트웨어 설계(226분)와 개발(242분)을 새 개발 과목에 일단 대응했지만 " +
                "2027 개편에서 범위 이동·삭제가 있어 정확한 대응이 아님.");
        return new CertificateEstimate(
                "정보처리기사 필기 — 2027~2029 출제기준 (4과목)",
                "2026년 합격자 1명의 과목별 직접 기록 + 공통 기출 430분의 모형 배분. " +
                "2027 과목 대응은 시험범위 개편을 완전히 반영하지 못한 잠정 모형.",
                "2027년 과목별 실측 합격자 0명, 이전 출제기준 1명만 참고. " +
                "과목당 50명 기준 미충족. 전체 합격자의 평균이나 필요 학습시간을 뜻하지 않습니다.",
                1436 / 60.0, 1, 0, "PROVISIONAL_LEGACY_MAPPING",
                List.of(new Observation(
                        "2026 정보처리기사 필기 합격자의 일자·과목별 기록", 2026, 1436 / 60.0,
                        "설계 226분, 개발 242분, DB 240분, 언어 117분, 구축관리 181분, " +
                        "공통 기출·오답 430분. 2027 4과목은 직접 실측 아님.",
                        false, IP_LOG_URL, true)), subjects);
    }

    /**
     * 2026 합격자: 모델링 단독 120분, SQL 단독 180분, 공통/혼합 840분.
     * 2025 재응시 합격자: 모델링 단독 180분, 공통 360분(산정에서는 제외).
     * SQLD는 2024 개정 이후 동일 2과목. 2026 학습일지 1건으로만
     * 19시간 전체를 과목별로 잠정 분해한다. 과목별 전체 시간 실측은 아니다.
     */
    public static CertificateEstimate sqld() {
        List<SubjectEstimate> calculated = proportionalCaseEstimate(
                List.of("데이터 모델링의 이해", "SQL 기본 및 활용"),
                new int[]{120, 180}, 840, 1, 1,
                "2026년 합격자 1명의 단독 과목시간 + 공통/혼합시간의 모형 배분",
                "원문: 모델링 단독 120분, SQL 단독 180분, 공통·혼합 840분. " +
                "2025년 다른 합격자의 모델링 단독 180분 기록은 별도 참고만 하고 " +
                "기준값 산정에는 섞지 않음.");
        List<SubjectEstimate> subjects = new ArrayList<>(calculated);
        SubjectEstimate model = subjects.get(0);
        // 모델링을 별도로 기록한 합격자 2명. 기준값 산출에는 2026 한 사람만 사용.
        subjects.set(0, new SubjectEstimate(model.name(), model.hours(),
                model.directlyRecordedHours(), 2, 2, model.referenceType(),
                model.derivation() + " [모델링 과목 단독 부분기록 추가 작성자 1명 확인]") );
        return new CertificateEstimate(
                "SQLD — 2024 개정 이후 (2과목)",
                "2026년 합격자 1명의 과목별 단독 활동시간 2h/3h 및 공통·혼합 14h를 " +
                "단독 활동시간 비율(2:3)로 배분한 시범 추정.",
                "2026년 자료 1명의 전체 공부시간 19시간을 임시 배분했습니다. " +
                "다른 2025년 재응시자 1명의 모델링 3시간 기록은 참고만 합니다. " +
                "과목 전체 학습 완료시간을 직접 잰 평균이 아니며 과목당 50명 기준 미충족입니다.",
                19, 1, 1, "PROVISIONAL_SHARED_ALLOCATION",
                List.of(
                        new Observation("2026 SQLD 합격자의 과목별·혼합 학습일지", 2026, 19,
                                "모델링 120분, SQL 180분, 혼합·취약점 복습 840분", false,
                                SQLD_LOG_URL, true),
                        new Observation("2025 SQLD 재응시 합격자 후기", 2025, 9,
                                "모델링 180분과 과목 불명 360분. 재응시자이므로 기준값 계산에서 제외", false,
                                SQLD_EXTRA_URL, false)), List.copyOf(subjects));
    }

    /** 단일 실기 과목 기록 1명, 통계적으로 대표성이 없음을 표시한다. */
    public static CertificateEstimate informationProcessingPractical() {
        return new CertificateEstimate(
                "정보처리기사 실기 — 정보처리 실무",
                "과목이 1개인 실기 합격 후기 1건의 자기보고 총 학습시간 그대로 사용",
                "실기 학습시간 1명 사례뿐이며 평균이 아닙니다. 50명 표본 기준 미충족입니다.",
                60.25, 1, 1, "PROVISIONAL_SINGLE_CASE",
                List.of(new Observation("2025 정보처리기사 실기 합격 후기", 2025, 60.25,
                        "60시간 15분 자기보고", false, IP_PRACTICAL_URL, true)),
                List.of(new SubjectEstimate("정보처리 실무", 60.25, 60.25,
                        1, 1, "실기 1인 사례 — 평균 아님",
                        "한 과목만 있는 실기. 작성자 1명의 전체 학습시간을 사용")));
    }

    private static List<SubjectEstimate> proportionalCaseEstimate(
            List<String> subjects, int[] directMinutes, int sharedMinutes,
            int directAuthors, int matchedStandardAuthors,
            String referenceType, String commonDerivation) {
        if (subjects.size() != directMinutes.length || sharedMinutes < 0)
            throw new IllegalArgumentException("후기 자료 구조 불일치");
        int totalDirect = 0;
        for (int value : directMinutes) {
            if (value <= 0) throw new IllegalArgumentException("과목별 기록시간이 필요합니다");
            totalDirect += value;
        }
        List<SubjectEstimate> results = new ArrayList<>();
        for (int i = 0; i < subjects.size(); i++) {
            double allocatedShared = sharedMinutes * ((double) directMinutes[i] / totalDirect);
            double estimated = (directMinutes[i] + allocatedShared) / 60.0;
            results.add(new SubjectEstimate(subjects.get(i), round2(estimated),
                    round2(directMinutes[i] / 60.0), directAuthors,
                    matchedStandardAuthors, referenceType,
                    "직접 식별 " + directMinutes[i] + "분 + 공통학습 " + sharedMinutes +
                    "분 중 비율배분 " + Math.round(allocatedShared) + "분. " + commonDerivation));
        }
        return List.copyOf(results);
    }

    private static double round2(double value) {
        return Math.round(value * 100.0) / 100.0;
    }
}
