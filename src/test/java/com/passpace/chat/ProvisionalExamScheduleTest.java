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
    @Test void expiredYearOrUnknownCertificateNeverInventsFutureDate() {
        assertNull(ProvisionalExamSchedule.forGoal("SQLD",LocalDate.of(2028,1,1)));
        assertNull(ProvisionalExamSchedule.forGoal("기타",LocalDate.of(2026,11,7)));
    }
}
