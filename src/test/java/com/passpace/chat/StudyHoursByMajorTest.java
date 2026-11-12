package com.passpace.chat;

import com.passpace.controller.MultiGoalPlannerController;
import com.passpace.controller.MultiGoalPlannerController.CatalogResponse;
import com.passpace.service.StudyHoursByMajor;
import com.passpace.service.StudyHoursByMajor.Qualification;
import com.passpace.auth.LoginUser;
import com.passpace.constant.SessionConst;
import com.passpace.constant.MajorType;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.http.ResponseEntity;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import org.springframework.jdbc.core.RowMapper;
//import static org.mockito.ArgumentMatchers.anyString;
//import static org.mockito.Mockito.*;

/** [동건] 전공 그룹 통계와 개인 이해도는 별개이며 세션으로 그룹을 결정한다. */
class StudyHoursByMajorTest {

    @Test
    void sourceCasesAreSeparatedWithoutInventingNonMajorAverage() {
        var counts = StudyHoursByMajor.counts(Qualification.IP_WRITTEN_2027);
        assertEquals(1, counts.major());
        assertEquals(0, counts.nonMajor());
        assertEquals(0, counts.sameSyllabusMajor());
        assertEquals(0, counts.sameSyllabusNonMajor());
        assertEquals(1, StudyHoursByMajor.subjectAuthors(Qualification.IP_WRITTEN_2027,
                MajorType.MAJOR, "소프트웨어 개발", false));
        assertEquals(0, StudyHoursByMajor.subjectAuthors(Qualification.IP_WRITTEN_2027,
                MajorType.MAJOR, "소프트웨어 개발", true));
        assertEquals(0, StudyHoursByMajor.subjectAuthors(Qualification.IP_WRITTEN_2027,
                MajorType.NON_MAJOR, "소프트웨어 개발", false));
    }

    @Test
    void unknownMajorSqldObservationsNeverBecomeMajorOrNonMajor() {
        var counts = StudyHoursByMajor.counts(Qualification.SQLD);
        assertEquals(0, counts.major());
        assertEquals(0, counts.nonMajor());
        assertEquals(2, counts.unclassified());
        var major = StudyHoursByMajor.resolve(Qualification.SQLD, MajorType.MAJOR);
        var nonMajor = StudyHoursByMajor.resolve(Qualification.SQLD, MajorType.NON_MAJOR);
        assertTrue(major.fallback());
        assertTrue(nonMajor.fallback());
        assertEquals(0, major.groupAuthors());
        assertEquals(0, nonMajor.groupAuthors());
        assertEquals("UNCLASSIFIED", nonMajor.sourceGroup());
        assertTrue(nonMajor.warning().contains("평균이 아닙니다"));
    }

    @Test
    void relatedMajorIsNotSilentlyMergedWithMajor() {
        var related = StudyHoursByMajor.resolve(Qualification.IP_WRITTEN_2027, MajorType.RELATED);
        assertEquals(0, related.groupAuthors());
        assertTrue(related.fallback());
        var major = StudyHoursByMajor.resolve(Qualification.IP_WRITTEN_2027, MajorType.MAJOR);
        assertEquals(1, major.groupAuthors());
        assertFalse(major.fallback());
        assertThrows(IllegalArgumentException.class,
                () -> StudyHoursByMajor.resolve(Qualification.SQLD, null));
    }

    @Test
    void catalogSelectsGroupFromSessionAndNotFromClient() {
//        JdbcTemplate jdbc = mock(JdbcTemplate.class);
//        when(jdbc.queryForList(anyString())).thenReturn(List.of());
        JdbcTemplate jdbc = new JdbcTemplate() {
            @Override
            public List<Map<String, Object>> queryForList(String sql) { return List.of(); }
            @Override
            public <T> List<T> query(String sql, RowMapper<T> rm, Object... args) { return List.of(); }
        };
        var controller = new MultiGoalPlannerController(jdbc);

        CatalogResponse major = (CatalogResponse) controller.catalog(session(MajorType.MAJOR)).getBody();
        CatalogResponse nonMajor = (CatalogResponse) controller.catalog(session(MajorType.NON_MAJOR)).getBody();
        assertNotNull(major);
        assertNotNull(nonMajor);
        assertEquals("MAJOR", major.loginMajor());
        assertEquals("NON_MAJOR", nonMajor.loginMajor());
        assertEquals(1, major.goals().stream().filter(g -> g.certificationName().startsWith("정보처리기사 필기"))
                .findFirst().orElseThrow().majorEvidence().groupAuthors());
        assertEquals(0, nonMajor.goals().stream().filter(g -> g.certificationName().startsWith("정보처리기사 필기"))
                .findFirst().orElseThrow().majorEvidence().groupAuthors());
        assertTrue(nonMajor.goals().stream().filter(g -> g.certificationName().startsWith("정보처리기사 필기"))
                .findFirst().orElseThrow().majorEvidence().fallback());
    }

    private MockHttpServletRequest session(MajorType major) {
        var request = new MockHttpServletRequest();
        var session = new MockHttpSession();
        session.setAttribute(SessionConst.LOGIN_USER, new LoginUser(1L, "test", "테스트", major));
        request.setSession(session);
        return request;
    }
}
