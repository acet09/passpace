package com.passpace.service;

import com.passpace.dto.cert.CertificationViews.CertDetail;
import com.passpace.dto.cert.CertificationViews.CertSummary;
import com.passpace.dto.cert.CertificationViews.NextEvent;
import com.passpace.dto.cert.CertificationViews.PassRate;
import com.passpace.dto.cert.CertificationViews.Round;
import com.passpace.repository.CertificationInfoQuery;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;

/** [11-26] 지원 자격증 정보 메뉴: 다음 일정·정렬·빈 값 처리 (DB·Spring 없이 확인) */
class CertificationInfoServiceTest {

    private static final LocalDate TODAY = LocalDate.of(2026, 11, 26);
    private static final Clock CLOCK = Clock.fixed(TODAY.atStartOfDay(ZoneId.of("Asia/Seoul")).toInstant(), ZoneId.of("Asia/Seoul"));

    private static CertificationInfoQuery.CertRow cert(long id, String name, String category, boolean alwaysOpen) {
        return new CertificationInfoQuery.CertRow(id, name, "국가기술자격", "기관", "평균 60점 이상", null, category,
                null, null, null, alwaysOpen, null, null, null, null, null, null, null, null, null, null);
    }

    private static Round round(String type, String regStart, String regEnd, String exam, String result) {
        return new Round(2026, 1, type, "WRITTEN".equals(type) ? "필기" : "실기",
                regStart == null ? null : LocalDate.parse(regStart).atTime(9, 0),
                regEnd == null ? null : LocalDate.parse(regEnd).atTime(18, 0), null, null,
                exam == null ? null : LocalDate.parse(exam), exam == null ? null : LocalDate.parse(exam),
                result == null ? null : LocalDate.parse(result), false, false);
    }

    /** 메모리 가짜 조회 */
    private static CertificationInfoQuery fake(List<CertificationInfoQuery.CertRow> certs, Map<Long, List<Round>> rounds) {
        return new CertificationInfoQuery() {
            public List<CertRow> findActive() { return certs; }
            public Optional<CertRow> findActive(long id) { return certs.stream().filter(c -> c.certificationId() == id).findFirst(); }
            public List<ExamInfoRow> findExamInfos(long id) {
                return id == 1 ? List.of(new ExamInfoRow("WRITTEN", null, null, null, null, null, null)) : List.of();
            }
            public Map<String, List<String>> findSubjects(long id) {
                return id == 1 ? Map.of("WRITTEN", List.of("과목1", "과목2"), "PRACTICAL", List.of("실무")) : Map.of();
            }
            public Map<Long, List<String>> findExamTypes() { return Map.of(1L, List.of("WRITTEN", "PRACTICAL")); }
            public List<Round> findRounds(long id, int fromYear, LocalDate today) { return rounds.getOrDefault(id, List.of()); }
            public Map<Long, List<Round>> findRoundsAll(int fromYear, LocalDate today) { return rounds; }
            public List<PassRate> findPassRates(long id, int limit) { return List.of(); }
        };
    }

    @Test
    void 접수_중이면_마감일이_다음_일정() {
        NextEvent e = CertificationInfoService.nextEvent(
                List.of(round("WRITTEN", "2026-11-20", "2026-11-30", "2026-12-20", "2027-01-10")), TODAY);
        assertEquals("REG_OPEN", e.kind());
        assertEquals(LocalDate.of(2026, 11, 30), e.date());
        assertEquals(4, e.dDay());
        assertEquals("필기 원서 접수 마감", e.label());
    }

    @Test
    void 지난_일정은_건너뛰고_가장_가까운_날() {
        NextEvent e = CertificationInfoService.nextEvent(List.of(
                round("WRITTEN", "2026-10-01", "2026-10-05", "2026-11-01", "2026-12-05"),
                round("PRACTICAL", "2026-12-01", "2026-12-04", "2027-01-10", "2027-02-01")), TODAY);
        assertEquals("REG_START", e.kind());
        assertEquals(LocalDate.of(2026, 12, 1), e.date());
    }

    @Test
    void 일정이_없으면_null() {
        assertNull(CertificationInfoService.nextEvent(List.of(), TODAY));
    }

    @Test
    void 목록은_가까운_일정순_상시와_일정없음은_뒤로() {
        var svc = new CertificationInfoService(fake(
                List.of(cert(1, "정보처리기사", "IT", false), cert(2, "SQLD", "데이터", false), cert(3, "컴활 1급", "사무·회계", true)),
                Map.of(1L, List.of(round("WRITTEN", "2027-01-10", "2027-01-15", "2027-02-10", null)),
                        2L, List.of(round("WRITTEN", "2026-12-01", "2026-12-05", "2026-12-20", null)))), CLOCK);
        List<CertSummary> list = svc.list(null, null);
        assertEquals(List.of(2L, 1L, 3L), list.stream().map(CertSummary::certificationId).toList());
        assertNull(list.get(2).nextEvent(), "상시 시험은 다음 일정 없음");
        assertEquals(1, svc.list("IT", null).size());
        assertEquals(1, svc.list(null, "sq ld").size());
    }

    @Test
    void 상세는_빈_값을_null로_두고_합격기준은_자격증_문장으로_대신() {
        var svc = new CertificationInfoService(fake(List.of(cert(1, "정보처리기사", "IT", false)), Map.of()), CLOCK);
        CertDetail d = svc.detail(1).orElseThrow();
        assertEquals(2, d.exams().size());
        assertEquals("WRITTEN", d.exams().get(0).examType());
        assertNull(d.exams().get(0).fee(), "응시료를 지어내지 않는다");
        assertEquals("평균 60점 이상", d.exams().get(0).passCriteria());
        assertEquals(List.of("실무"), d.exams().get(1).subjects());
        assertNull(d.nextExam());
        assertTrue(svc.detail(99).isEmpty());
    }
}
