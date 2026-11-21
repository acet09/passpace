package com.passpace.collect;

import com.passpace.service.SubjectStudyExtractor;
import com.passpace.service.SubjectStudyExtractor.Mention;
import com.passpace.service.SubjectStudyExtractor.MentionType;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** [용성 · 11-16] 과목별 공부 정보 추출 테스트 - DB·Spring 없이 실행된다 */
class SubjectStudyExtractorTest {

    private final SubjectStudyExtractor extractor = new SubjectStudyExtractor();

    private static Mention find(List<Mention> list, String subject, MentionType type) {
        return list.stream().filter(m -> m.subjectName().equals(subject) && m.type() == type).findFirst().orElse(null);
    }

    @Test
    void 과목_뒤의_시간을_뽑는다() {
        List<Mention> r = extractor.extract("데이터베이스는 10시간 정도 봤고 프로그래밍 언어는 5시간 했어요.", null, null);
        assertEquals(0, new BigDecimal("10").compareTo(find(r, "데이터베이스 구축", MentionType.HOURS).hours()));
        assertEquals(0, new BigDecimal("5").compareTo(find(r, "프로그래밍 언어 활용", MentionType.HOURS).hours()));
        assertTrue(r.stream().noneMatch(Mention::estimated));
    }

    @Test
    void 일수는_하루_공부시간으로_환산하고_추정값으로_표시한다() {
        List<Mention> r = extractor.extract("DB는 3일 정도 잡고 했어요.", 240, null);
        Mention m = find(r, "데이터베이스 구축", MentionType.HOURS);
        assertEquals(0, new BigDecimal("12").compareTo(m.hours()));
        assertTrue(m.estimated());
    }

    @Test
    void 하루_공부시간을_모르면_일수를_시간으로_바꾸지_않는다() {
        List<Mention> r = extractor.extract("DB는 3일 정도 잡고 했어요.", null, null);
        assertNull(find(r, "데이터베이스 구축", MentionType.HOURS));
    }

    @Test
    void 기본_하루시간을_주면_그_값으로_환산한다() {
        List<Mention> r = new SubjectStudyExtractor(120).extract("DB는 이틀 봤어요.", null, null);
        assertEquals(0, new BigDecimal("4").compareTo(find(r, "데이터베이스 구축", MentionType.HOURS).hours()));
    }

    @Test
    void 하루_공부시간_표현은_과목_시간으로_보지_않는다() {
        List<Mention> r = extractor.extract("데이터베이스는 하루 2시간씩 봤어요.", null, null);
        assertNull(find(r, "데이터베이스 구축", MentionType.HOURS));
    }

    @Test
    void 비율과_절반을_뽑는다() {
        List<Mention> r = extractor.extract("전체 시간 중 데이터베이스에 40% 썼고 소프트웨어 개발에 절반 정도 썼어요.", null, null);
        assertEquals(0, new BigDecimal("40").compareTo(find(r, "데이터베이스 구축", MentionType.RATIO).ratioPercent()));
        assertEquals(0, new BigDecimal("50").compareTo(find(r, "소프트웨어 개발", MentionType.RATIO).ratioPercent()));
    }

    @Test
    void 건너뛴_과목은_0시간이다() {
        List<Mention> r = extractor.extract("전공이라 데이터베이스랑 프로그래밍 언어는 건너뛰었어요.", null, null);
        assertEquals(0, BigDecimal.ZERO.compareTo(find(r, "데이터베이스 구축", MentionType.SKIPPED).hours()));
        assertEquals(0, BigDecimal.ZERO.compareTo(find(r, "프로그래밍 언어 활용", MentionType.SKIPPED).hours()));
    }

    @Test
    void 어려움과_쉬움을_구분한다() {
        List<Mention> r = extractor.extract("데이터베이스 과목이 제일 어려웠습니다. 소프트웨어 개발은 어렵지 않았어요.", null, null);
        assertTrue(find(r, "데이터베이스 구축", MentionType.DIFFICULT) != null);
        assertTrue(find(r, "소프트웨어 개발", MentionType.EASY) != null);
        assertNull(find(r, "소프트웨어 개발", MentionType.DIFFICULT));
    }

    @Test
    void 과목_시간_합이_총시간보다_크면_시간값을_버린다() {
        List<Mention> r = extractor.extract("DB 20시간, 소프트웨어 개발 15시간 했어요.", null, new BigDecimal("30"));
        assertTrue(r.stream().noneMatch(m -> m.type() == MentionType.HOURS));
    }

    @Test
    void 과목_언급이_없으면_빈_목록() {
        assertTrue(extractor.extract("두 달 동안 하루 2시간 공부했어요. 총 120시간.", 120, null).isEmpty());
        assertTrue(extractor.extract(null, null, null).isEmpty());
    }

    @Test
    void 옛_과목_소프트웨어_설계는_이름_그대로_남긴다() {
        List<Mention> r = extractor.extract("소프트웨어 설계는 6시간 봤어요.", null, null);
        assertEquals(0, new BigDecimal("6").compareTo(find(r, "소프트웨어 설계", MentionType.HOURS).hours()));
    }

    @Test
    void 근거는_원문이_아니라_요약문이다() {
        List<Mention> r = extractor.extract("DB는 3일 정도 잡고 했어요.", 240, null);
        assertEquals("데이터베이스 구축: 3일 × 하루 240분 ≈ 12시간(환산)", find(r, "데이터베이스 구축", MentionType.HOURS).evidence());
    }

    @Test
    void 동안_봤다는_건너뜀이_아니다() {
        List<Mention> r = extractor.extract("SQL 기본은 5일 동안 봤어요. DB 파트는 1일차에 끝냈어요.", 120, null);
        assertNull(find(r, "SQL 기본 및 활용", MentionType.SKIPPED));
        assertEquals(0, new BigDecimal("10").compareTo(find(r, "SQL 기본 및 활용", MentionType.HOURS).hours()));
        assertNull(find(r, "데이터베이스 구축", MentionType.HOURS));   // "1일차"는 기간이 아님
    }

    // ---- [11-16 보정] 실제 수집 결과에서 나온 오인식 (원문 표현을 줄여 옮김) ----

    @Test
    void 합격_기준_과목별_40퍼센트는_비율이_아니다() {
        List<Mention> r = extractor.extract("합격 기준은 총점 60점 이상, 과목별 40% 이상입니다. SQL 기본 및 활용 과목 40% 미만이면 과락.", null, null);
        assertNull(find(r, "SQL 기본 및 활용", MentionType.RATIO));
    }

    @Test
    void 백퍼센트_맞춘다는_비율이_아니다() {
        List<Mention> r = extractor.extract("이론 + DB 영역은 100% 맞춘다", null, null);
        assertNull(find(r, "데이터베이스 구축", MentionType.RATIO));
    }

    @Test
    void 강의_수강기간은_과목_공부일수가_아니다() {
        List<Mention> r = extractor.extract("프로그래밍 언어 특강만 들음. 실기강의 90일정도 들을 수 있기 때문에 여유있게 했음", 510, null);
        assertNull(find(r, "프로그래밍 언어 활용", MentionType.HOURS));
    }

    @Test
    void 과목_일수가_너무_길면_버린다() {
        List<Mention> r = extractor.extract("데이터베이스는 60일 동안 공부했어요.", 120, null);
        assertNull(find(r, "데이터베이스 구축", MentionType.HOURS));
    }

    @Test
    void 과목_이름에서_먼_말은_그_과목에_붙이지_않는다() {
        List<Mention> r = extractor.extract("데이터베이스는 정규화랑 SQL 문법 위주로 기출 반복해서 정리했고 마지막 주에는 다른 과목 복습하면서 정말 어려웠어요.", null, null);
        assertNull(find(r, "데이터베이스 구축", MentionType.DIFFICULT));
    }

    @Test
    void 시간을_쓴_비율은_그대로_뽑는다() {
        List<Mention> r = extractor.extract("공부 시간의 30% 정도를 데이터베이스에 투자했어요. 프로그래밍 언어는 시간의 절반을 썼어요.", null, null);
        assertNull(find(r, "데이터베이스 구축", MentionType.RATIO));   // 비율이 과목 이름 앞에 있으면 아직 못 잡음
        assertEquals(0, new BigDecimal("50").compareTo(find(r, "프로그래밍 언어 활용", MentionType.RATIO).ratioPercent()));
    }

    @Test
    void 시험_시간_안내는_공부시간이_아니다() {
        List<Mention> r = extractor.extract("실기 출제기준은 과목명 정보처리 실무, 필답형, 2시간 30분으로 같다. 데이터베이스 포함 80문항을 2시간 안에 푸는 연습", null, null);
        assertNull(find(r, "정보처리 실무", MentionType.HOURS));
        assertNull(find(r, "데이터베이스 구축", MentionType.HOURS));
    }

    // ---------------- [11-19] 학습일지 합산 ----------------

    @Test
    void 학습일지_표는_같은_과목_시간을_합산한다() {
        // hwankr 정처기 필기 후기와 같은 표 형식 (날짜 | 공부 시간 | 내용)
        String log = String.join("\n",
                "| 날짜 | 공부 시간 | 내용 |",
                "| 2026-07-28 | 3h 46m | 1과목 소프트웨어 설계 |",
                "| 2026-07-29 | 4h 02m | 2과목 소프트웨어 개발 |",
                "| 2026-07-30 | 2h 10m | 3과목 데이터베이스 구축 |",
                "| 2026-08-02 | 1시간 50분 | 데이터베이스 구축 복습 |",
                "| 2026-08-06 | 2h 38m | 2024년 3회 기출 |",
                "| **합계** | **23h 56m** | **7일** |");
        List<Mention> r = extractor.extract(log, null, new BigDecimal("23.93"));
        assertEquals(0, new BigDecimal("4.00").compareTo(find(r, "데이터베이스 구축", MentionType.HOURS).hours()));   // 2h10m + 1시간 50분
        assertEquals(0, new BigDecimal("3.77").compareTo(find(r, "소프트웨어 설계", MentionType.HOURS).hours()));
        assertEquals(0, new BigDecimal("4.03").compareTo(find(r, "소프트웨어 개발", MentionType.HOURS).hours()));
        assertTrue(find(r, "데이터베이스 구축", MentionType.HOURS).evidence().contains("학습일지 2줄 합산"));
    }

    @Test
    void 날짜줄이_3줄_미만이면_일지로_보지_않는다() {
        List<Mention> r = extractor.extract("2026-07-28 DB 3h\n2026-07-29 DB 2h", null, null);
        assertNull(find(r, "데이터베이스 구축", MentionType.HOURS));
    }

    @Test
    void 일지_한_줄에_과목이_여럿이면_나누지_않는다() {
        List<Mention> r = extractor.extract("7/28 DB 2시간\n7/29 DB와 프로그래밍 언어 3시간\n7/30 프로그래밍 언어 1시간 30분", null, null);
        assertEquals(0, new BigDecimal("2.00").compareTo(find(r, "데이터베이스 구축", MentionType.HOURS).hours()));
        assertEquals(0, new BigDecimal("1.50").compareTo(find(r, "프로그래밍 언어 활용", MentionType.HOURS).hours()));
    }

    @Test
    void 일지의_시각_범위는_공부시간으로_읽지_않는다() {
        List<Mention> r = extractor.extract("1일차 DB 19:00~21:00\n2일차 DB 1:30\n3일차 DB 90분", null, null);
        assertEquals(0, new BigDecimal("3.00").compareTo(find(r, "데이터베이스 구축", MentionType.HOURS).hours()));   // 1:30 + 90분
    }
}
