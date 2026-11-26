package com.passpace.collect;

import com.passpace.service.CandidateProbeServiceTestAccess;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** [11-24] 새 자격증 후보 시험 실행: 키워드 판별, 예상치 계산, 시간 초과, DB 미사용 */
class CandidateProbeServiceTest {

    @Test
    void 판별키워드가_있어야_대상() {
        assertEquals("OK", CandidateProbeServiceTestAccess.classify("산업안전기사", "산업안전기사 필기 합격 후기", ""));
        assertEquals("OK", CandidateProbeServiceTestAccess.classify("산업안전기사", "산안기 3주 합격", ""));
        assertEquals("NO_KEYWORD", CandidateProbeServiceTestAccess.classify("산업안전기사", "건강검진 후기", "병원"));
    }

    @Test
    void 제목에_제외키워드가_있으면_뺀다() {
        assertEquals("EXCLUDED", CandidateProbeServiceTestAccess.classify("산업안전기사", "산업안전산업기사 합격 후기", "산업안전기사 말고"));
        assertEquals("EXCLUDED", CandidateProbeServiceTestAccess.classify("전산회계 1급", "전산회계 2급, 1급 동시 합격", "전산회계 1급"));
        // 요약에만 있으면 대상으로 두고 "섞임"으로 표시한다
        assertEquals("OK", CandidateProbeServiceTestAccess.classify("전산회계 1급", "전산회계1급 합격 후기", "2급 따고 바로 전산세무 준비"));
        assertTrue(CandidateProbeServiceTestAccess.mixed("전산회계 1급", "2급 따고 바로 전산세무 준비"));
    }

    @Test
    void 영문_약어는_단어로만_맞춘다() {
        // "ADP" 가 "ADsP" 안에서 잘못 맞지 않는다
        assertFalse(CandidateProbeServiceTestAccess.containsWord("adsp합격", "adp"));
        assertTrue(CandidateProbeServiceTestAccess.containsWord("adp합격", "adp"));
        assertTrue(CandidateProbeServiceTestAccess.containsWord("빅분기adsp다음", "adsp"));
    }

    @Test
    void 기존_4종과_함께_나오면_섞임() {
        assertTrue(CandidateProbeServiceTestAccess.mixed("산업안전기사", "정처기 이어서 산업안전기사"));
        assertFalse(CandidateProbeServiceTestAccess.mixed("산업안전기사", "산업안전기사 실기 합격"));
    }

    @Test
    void 예상치와_신뢰구간() {
        long[] e = CandidateProbeServiceTestAccess.estimate(2000, 30, 100);
        assertEquals(600, e[0]);
        assertTrue(e[1] < 600 && e[2] > 600);
        assertEquals(0, CandidateProbeServiceTestAccess.estimate(2000, 0, 0)[0]);
        assertEquals("가능", CandidateProbeServiceTestAccess.verdict(500));
        assertEquals("보류", CandidateProbeServiceTestAccess.verdict(300));
        assertEquals("불가", CandidateProbeServiceTestAccess.verdict(299));
    }

    @Test
    void 영문코드로_자격증을_지정한다() {
        assertEquals("산업안전기사", CandidateProbeServiceTestAccess.resolve("SAFETY"));
        assertEquals("전산회계 1급", CandidateProbeServiceTestAccess.resolve(" accounting "));
        assertEquals("빅데이터분석기사", CandidateProbeServiceTestAccess.resolve("빅데이터분석기사"));
    }

    @Test
    void 표본은_최근3년글_먼저() {
        assertTrue(CandidateProbeServiceTestAccess.sampleTakesRecentFirst());
    }

    @Test
    void 시간초과_판정은_건너뛴다() throws Exception {
        assertTrue(CandidateProbeServiceTestAccess.timeoutSkips());
    }

    @Test
    void DB에_쓰지_않는다_리포지토리를_주입받지_않음() {
        assertTrue(CandidateProbeServiceTestAccess.hasNoRepositoryDependency());
    }
}
