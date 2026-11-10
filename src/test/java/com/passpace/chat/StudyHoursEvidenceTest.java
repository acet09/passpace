package com.passpace.chat;

import com.passpace.chat.service.StudyHoursEvidence;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/** [동건] 별도 추가 테스트: 데이터 표본 수, 공식 과목명, 잠정 값과 실제 측정의 구분. */
class StudyHoursEvidenceTest {
    @Test
    void informationProcessingWrittenUses2027FourSubjectsAndDisclosesNoDirect2027Sample() {
        var e = StudyHoursEvidence.informationProcessingWritten2027();
        assertEquals(List.of("소프트웨어 개발", "데이터베이스 구축", "프로그래밍 언어 활용", "정보시스템 구축관리"),
                e.subjects().stream().map(StudyHoursEvidence.SubjectEstimate::name).toList());
        assertEquals(0, e.matchingSyllabusAuthors());
        assertEquals(1, e.baselineAuthors());
        assertEquals(23.93, e.subjects().stream().mapToDouble(
                StudyHoursEvidence.SubjectEstimate::hours).sum(), 0.02);
        assertTrue(e.warning().contains("평균"));
    }

    @Test
    void sqldKeepsOnlyCurrentTwoSubjectsAndDoesNotUseRetakeToComputeBaseline() {
        var e = StudyHoursEvidence.sqld();
        assertEquals(List.of("데이터 모델링의 이해", "SQL 기본 및 활용"),
                e.subjects().stream().map(StudyHoursEvidence.SubjectEstimate::name).toList());
        assertEquals(7.6, e.subjects().get(0).hours(), 0.01);
        assertEquals(11.4, e.subjects().get(1).hours(), 0.01);
        assertEquals(2, e.subjects().get(0).directAuthorCount());
        assertEquals(1, e.subjects().get(1).directAuthorCount());
        assertEquals(1, e.observations().stream().filter(
                StudyHoursEvidence.Observation::usedForBaseline).count());
    }

    @Test
    void allSourcesAreExternalEvidenceAndNoSubjectClaimIsFiftyPersonAverage() {
        for (var e : List.of(StudyHoursEvidence.informationProcessingWritten2027(),
                StudyHoursEvidence.sqld(), StudyHoursEvidence.informationProcessingPractical())) {
            assertTrue(e.baselineAuthors() < 50);
            assertTrue(e.observations().stream().allMatch(o -> o.url().startsWith("https://")));
            assertTrue(e.subjects().stream().allMatch(s -> s.hours() > 0));
            assertTrue(e.warning().contains("50명"));
        }
    }
}
