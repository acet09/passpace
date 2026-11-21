package com.passpace.chat;

import com.passpace.service.ProvisionalExamSchedule;
import org.junit.jupiter.api.Test;
import java.time.LocalDate;
import static org.junit.jupiter.api.Assertions.*;

class ProvisionalExamScheduleTest {
    @Test void nextYearProvisionalTargetsAreClearlyLabeled() {
        var today=LocalDate.of(2026,11,7);
        var ip=ProvisionalExamSchedule.forGoal("정보처리기사 필기 (2027~)",today);
        var sql=ProvisionalExamSchedule.forGoal("SQLD",today);
        assertEquals(LocalDate.of(2027,3,3),ip.targetDate());
        assertEquals(LocalDate.of(2027,3,7),sql.targetDate());
        assertTrue(ip.notice().contains("공식 시험일 아님"));
        assertTrue(sql.notice().contains("2026"));
    }
    @Test void adspUsesFirstRoundOf2026AndAnytimeExamGetsNoInventedDate() {
        var today=LocalDate.of(2026,11,15);
        var adsp=ProvisionalExamSchedule.forGoal("ADsP",today);
        assertEquals(LocalDate.of(2027,2,7),adsp.targetDate());
        assertTrue(adsp.notice().contains("공식 시험일 아님"));
        // 컴활은 상시시험: 날짜를 지어내지 않고 안내만 한다
        assertNull(ProvisionalExamSchedule.forGoal("컴퓨터활용능력 1급 필기",today));
        var anytime=ProvisionalExamSchedule.anytimeExam("컴퓨터활용능력 1급 실기");
        assertNull(anytime.targetDate());
        assertTrue(anytime.notice().contains("상시시험"));
        assertNull(ProvisionalExamSchedule.anytimeExam("ADsP"));
    }
    @Test void expiredYearOrUnknownCertificateNeverInventsFutureDate() {
        assertNull(ProvisionalExamSchedule.forGoal("SQLD",LocalDate.of(2028,1,1)));
        assertNull(ProvisionalExamSchedule.forGoal("기타",LocalDate.of(2026,11,7)));
    }
}
