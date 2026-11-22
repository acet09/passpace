package com.passpace.controller;

import com.passpace.constant.ExamType;
import com.passpace.constant.MajorType;
import com.passpace.controller.MultiGoalPlannerController.GoalCatalog;
import com.passpace.controller.MultiGoalPlannerController.SubjectCatalog;
import com.passpace.domain.StudyReference;
import com.passpace.domain.StudyReference.SubjectHours;
import com.passpace.service.MultiGoalPlanCalculator;
import com.passpace.service.MultiGoalPlanCalculator.GoalInput;
import com.passpace.service.MultiGoalPlanCalculator.PlanRequest;
import com.passpace.service.MultiGoalPlanCalculator.PlanResponse;
import com.passpace.service.MultiGoalPlanCalculator.SubjectInput;
import com.passpace.service.StudyHoursByMajor;
import com.passpace.service.StudyHoursByMajor.Qualification;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/** [동건] 크롤링 후기 실측 평균 → 과목별 기준시간 → 계획 계산 연결 (DB·Spring 없이 확인) */
class ReviewBasedPlannerControllerTest {

    /** 기존 플래너가 만드는 SQLD 항목 (블로그 1건 기반 잠정값 7.6h / 11.4h) */
    private static GoalCatalog legacySqld(MajorType major) {
        var byMajor = StudyHoursByMajor.resolve(Qualification.SQLD, major);
        List<SubjectCatalog> subjects = byMajor.reference().subjects().stream().map(s ->
                new SubjectCatalog(null, s.name(), s.hours(), true, s.referenceType(), s.directlyRecordedHours(),
                        s.directAuthorCount(), s.matchingSyllabusAuthors(), s.derivation(), 0, 0)).toList();
        return new GoalCatalog("db-2-WRITTEN", "SQLD", "WRITTEN", false, subjects, byMajor.reference(), byMajor,
                LocalDate.of(2027, 3, 6), "안내", "");
    }

    /** 후기 25건 평균 40시간을 잠정 비율 2:3 으로 나눈 값 (JdbcStudyReferenceQuery 가 돌려주는 모양) */
    private static StudyReference verifiedSqld(MajorType applied) {
        return new StudyReference(2, ExamType.WRITTEN, applied, 40.0, 25, 2.0, 120.0, true,
                "합격 후기 25건(작성자당 1건, 최근 3년) 실측 평균",
                List.of(new SubjectHours(6, "데이터 모델링의 이해", 16.0, "실측 × 비율"),
                        new SubjectHours(7, "SQL 기본 및 활용", 24.0, "실측 × 비율")));
    }

    @Test
    void 후기_실측_평균이_있으면_과목별_기준시간이_그_값으로_바뀐다() {
        GoalCatalog legacy = legacySqld(MajorType.NON_MAJOR);
        GoalCatalog goal = ReviewBasedPlannerController.applyReference(legacy, verifiedSqld(null), MajorType.NON_MAJOR);

        assertTrue(ReviewBasedPlannerController.isReviewBased(goal));
        assertEquals(List.of(16.0, 24.0), goal.subjects().stream().map(SubjectCatalog::baseHours).toList());
        assertEquals(List.of(6L, 7L), goal.subjects().stream().map(SubjectCatalog::subjectId).toList());
        assertEquals(40.0, goal.evidence().referenceTotalHours());
        assertEquals(25, goal.evidence().baselineAuthors());
        // 전공 구분 없는 전체 후기를 쓴 것이므로 "내 집단 평균"으로 표시하지 않는다
        assertTrue(goal.majorEvidence().fallback());
        assertEquals(0, goal.majorEvidence().groupAuthors());
        // 시험일 등 나머지는 기존 값 그대로
        assertEquals(legacy.suggestedExamDate(), goal.suggestedExamDate());
        assertEquals(legacy.key(), goal.key());
    }

    @Test
    void 내_전공_집단_후기가_충분하면_같은_집단_평균으로_표시한다() {
        GoalCatalog goal = ReviewBasedPlannerController.applyReference(
                legacySqld(MajorType.NON_MAJOR), verifiedSqld(MajorType.NON_MAJOR), MajorType.NON_MAJOR);
        assertFalse(goal.majorEvidence().fallback());
        assertEquals(25, goal.majorEvidence().groupAuthors());
        assertEquals("REVIEW_VERIFIED_SAME_GROUP", goal.majorEvidence().status());
    }

    @Test
    void 후기가_부족하거나_과목이_맞지_않으면_기존_값을_그대로_쓴다() {
        GoalCatalog legacy = legacySqld(MajorType.MAJOR);
        assertSame(legacy, ReviewBasedPlannerController.applyReference(legacy, null, MajorType.MAJOR));

        StudyReference provisional = new StudyReference(2, ExamType.WRITTEN, null, 19.0, 1, null, null, false, "잠정",
                verifiedSqld(null).subjects());
        assertSame(legacy, ReviewBasedPlannerController.applyReference(legacy, provisional, MajorType.MAJOR));

        StudyReference otherSubjects = new StudyReference(2, ExamType.WRITTEN, null, 40.0, 25, 2.0, 120.0, true, "실측",
                List.of(new SubjectHours(6, "데이터 모델링의 이해", 16.0, ""), new SubjectHours(9, "다른 과목", 24.0, "")));
        assertSame(legacy, ReviewBasedPlannerController.applyReference(legacy, otherSubjects, MajorType.MAJOR));
        assertFalse(ReviewBasedPlannerController.isReviewBased(legacy));
    }

    @Test
    void 계획은_브라우저_값이_아니라_후기_기반_서버_시간으로_계산한다() {
        GoalCatalog goal = ReviewBasedPlannerController.applyReference(
                legacySqld(MajorType.NON_MAJOR), verifiedSqld(null), MajorType.NON_MAJOR);
        LocalDate today = LocalDate.of(2027, 1, 4);
        PlanRequest fromBrowser = new PlanRequest(120, List.of(new GoalInput("db-2-WRITTEN", "SQLD",
                today.plusDays(60), List.of(
                new SubjectInput("데이터 모델링의 이해", 1.0, 2, 0, 0),      // 브라우저가 1시간으로 줄여 보냄
                new SubjectInput("SQL 기본 및 활용", 1.0, 1, 0, 0)), null)));

        PlanRequest accepted = ReviewBasedPlannerController.withServerHours(fromBrowser, List.of(goal));
        assertEquals(List.of(16.0, 24.0),
                accepted.goals().get(0).subjects().stream().map(SubjectInput::baseHours).toList());

        PlanResponse plan = new MultiGoalPlanCalculator().calculate(accepted, today);
        // 16h × 1.0(보통) + 24h × 1.3(낮음) = 47.2h = 2832분
        assertEquals(2832, plan.totalRemainingMinutes());
        assertTrue(plan.feasible());
        assertFalse(plan.days().isEmpty());
        assertTrue(ReviewBasedPlannerController.summarize(plan, List.of(goal)).contains("전공 구분 없는 전체 합격 후기 25건 실측 평균 40.0시간"));
        assertTrue(ReviewBasedPlannerController.summarize(plan, List.of(goal)).contains("SQL 기본 및 활용: 후기 평균 24.0시간 × 이해도 1.3 = 31.2시간"));
    }

    /** 기존 플래너가 만드는 임의 자격증 항목 */
    private static GoalCatalog legacy(String key, String name, String examType, Qualification qualification) {
        var byMajor = StudyHoursByMajor.resolve(qualification, MajorType.NON_MAJOR);
        List<SubjectCatalog> subjects = byMajor.reference().subjects().stream().map(s ->
                new SubjectCatalog(null, s.name(), s.hours(), true, s.referenceType(), s.directlyRecordedHours(),
                        s.directAuthorCount(), s.matchingSyllabusAuthors(), s.derivation(), 0, 0)).toList();
        return new GoalCatalog(key, name, examType, false, subjects, byMajor.reference(), byMajor, null, "안내", "");
    }

    /** 카탈로그 항목 그대로 계획 요청을 만든다 (모든 과목 이해도 보통) */
    private static GoalInput request(GoalCatalog goal, LocalDate examDate) {
        return new GoalInput(goal.key(), goal.certificationName(), examDate, goal.subjects().stream()
                .map(s -> new SubjectInput(s.name(), 1.0, 2, 0, 0)).toList(), null);
    }

    @Test
    void 과목_비율은_고정값이_아니라_수집_데이터_기준_ref_시간을_그대로_쓴다() {
        // 고정 비율(StudyHoursEvidence)은 모델링 2 : SQL 3 이지만, 수집 데이터 집계는 1 : 3 으로 준다
        StudyReference collected = new StudyReference(2, ExamType.WRITTEN, null, 40.0, 25, 2.0, 120.0, true,
                "합격 후기 25건 실측 중앙값", List.of(
                new SubjectHours(6, "데이터 모델링의 이해", 10.0, "총 학습시간 실측 25건 중앙값 × 과목 비율"),
                new SubjectHours(7, "SQL 기본 및 활용", 30.0, "총 학습시간 실측 25건 중앙값 × 과목 비율")));
        GoalCatalog goal = ReviewBasedPlannerController.applyReference(
                legacySqld(MajorType.NON_MAJOR), collected, MajorType.NON_MAJOR);

        assertTrue(ReviewBasedPlannerController.isReviewBased(goal));
        assertEquals(List.of(10.0, 30.0), goal.subjects().stream().map(SubjectCatalog::baseHours).toList());
        assertTrue(goal.subjects().get(1).derivation().contains("이 과목 비율 75%"));
        assertTrue(goal.subjects().get(1).derivation().contains("수집 데이터 집계 기준"));
    }

    @Test
    void ADsP도_ref가_주는_과목_시간을_그대로_쓴다() {
        GoalCatalog adsp = legacy("db-4-WRITTEN", "ADsP", "WRITTEN", Qualification.ADSP);
        StudyReference ref = new StudyReference(4, ExamType.WRITTEN, null, 30.0, 58, 3.0, 360.0, true,
                "합격 후기 58건 실측 중앙값", List.of(new SubjectHours(15, "데이터 이해", 6.0, ""),
                new SubjectHours(16, "데이터분석 기획", 6.0, ""), new SubjectHours(17, "데이터분석", 18.0, "")));
        GoalCatalog goal = ReviewBasedPlannerController.applyReference(adsp, ref, MajorType.NON_MAJOR);

        assertTrue(ReviewBasedPlannerController.isReviewBased(goal));
        assertEquals(List.of(6.0, 6.0, 18.0), goal.subjects().stream().map(SubjectCatalog::baseHours).toList());
        assertEquals(List.of(15L, 16L, 17L), goal.subjects().stream().map(SubjectCatalog::subjectId).toList());
    }

    @Test
    void ref에_과목_시간이_없거나_과목_수가_다르면_고정값을_그대로_쓴다() {
        GoalCatalog adsp = legacy("db-4-WRITTEN", "ADsP", "WRITTEN", Qualification.ADSP);
        // 과목 시간이 비어 있음 (0)
        StudyReference emptyHours = new StudyReference(4, ExamType.WRITTEN, null, 30.0, 58, 3.0, 360.0, true, "실측",
                List.of(new SubjectHours(15, "데이터 이해", 0, ""), new SubjectHours(16, "데이터분석 기획", 6.0, ""),
                        new SubjectHours(17, "데이터분석", 18.0, "")));
        assertSame(adsp, ReviewBasedPlannerController.applyReference(adsp, emptyHours, MajorType.NON_MAJOR));
        // 과목 수가 다름 (3과목인데 2과목만)
        StudyReference fewer = new StudyReference(4, ExamType.WRITTEN, null, 30.0, 58, 3.0, 360.0, true, "실측",
                List.of(new SubjectHours(15, "데이터 이해", 10.0, ""), new SubjectHours(17, "데이터분석", 20.0, "")));
        assertSame(adsp, ReviewBasedPlannerController.applyReference(adsp, fewer, MajorType.NON_MAJOR));
        // 고정값(공식 문항 수 비율 10:10:30)이 그대로 남는다
        assertEquals(List.of(8.74, 8.74, 26.22), adsp.subjects().stream().map(SubjectCatalog::baseHours).toList());
    }

    @Test
    void 자격증은_세_개까지_묶고_필기와_실기는_한_개로_센다() {
        GoalCatalog ipeWritten = legacy("db-1-WRITTEN", "정보처리기사 필기 (2027~)", "WRITTEN", Qualification.IP_WRITTEN_2027);
        GoalCatalog ipePractical = legacy("db-1-PRACTICAL", "정보처리기사 실기", "PRACTICAL", Qualification.IP_PRACTICAL);
        GoalCatalog sqld = legacy("db-2-WRITTEN", "SQLD", "WRITTEN", Qualification.SQLD);
        GoalCatalog caWritten = legacy("db-3-WRITTEN", "컴퓨터활용능력 1급 필기", "WRITTEN", Qualification.CA1_WRITTEN);
        GoalCatalog caPractical = legacy("db-3-PRACTICAL", "컴퓨터활용능력 1급 실기", "PRACTICAL", Qualification.CA1_PRACTICAL);
        GoalCatalog adsp = legacy("db-4-WRITTEN", "ADsP", "WRITTEN", Qualification.ADSP);
        List<GoalCatalog> catalog = List.of(ipeWritten, ipePractical, sqld, caWritten, caPractical, adsp);
        LocalDate exam = LocalDate.of(2027, 3, 6);

        // 자격증 3개(정처기 필기+실기, 컴활 필기+실기, SQLD) = 목표 5개 → 허용
        PlanRequest five = new PlanRequest(180, List.of(request(ipeWritten, exam), request(ipePractical, exam),
                request(caWritten, exam), request(caPractical, exam), request(sqld, exam)));
        assertEquals(5, ReviewBasedPlannerController.withServerHours(five, catalog).goals().size());

        // 자격증 4개 → 거절
        PlanRequest four = new PlanRequest(180, List.of(request(ipeWritten, exam), request(sqld, exam),
                request(caWritten, exam), request(adsp, exam)));
        var error = assertThrows(IllegalArgumentException.class,
                () -> ReviewBasedPlannerController.withServerHours(four, catalog));
        assertTrue(error.getMessage().contains("최대 3개"));
    }

    @Test
    void 정처기_SQLD_ADsP_세_개를_하루_시간을_나눠_한_계획으로_만든다() {
        GoalCatalog ipe = legacy("db-1-WRITTEN", "정보처리기사 필기 (2027~)", "WRITTEN", Qualification.IP_WRITTEN_2027);
        GoalCatalog sqld = legacy("db-2-WRITTEN", "SQLD", "WRITTEN", Qualification.SQLD);
        GoalCatalog adsp = legacy("db-4-WRITTEN", "ADsP", "WRITTEN", Qualification.ADSP);
        LocalDate today = LocalDate.of(2026, 11, 16);
        // 시험일이 서로 다르다: ADsP 2/7 → 정처기 3/3 → SQLD 3/7
        PlanRequest fromBrowser = new PlanRequest(120, List.of(request(ipe, LocalDate.of(2027, 3, 3)),
                request(sqld, LocalDate.of(2027, 3, 7)), request(adsp, LocalDate.of(2027, 2, 7))),
                List.of(1, 2, 3, 4, 5));
        PlanRequest accepted = ReviewBasedPlannerController.withServerHours(fromBrowser, List.of(ipe, sqld, adsp));
        PlanResponse plan = new MultiGoalPlanCalculator().calculate(accepted, today);

        // 23.93h + 19h + 43.7h, 과목별로 분 단위 올림 (브라우저가 보낸 1시간이 아니라 서버 기준시간)
        assertEquals(1437 + 1140 + 2624, plan.totalRemainingMinutes());
        assertTrue(plan.feasible());
        assertEquals(List.of("ADsP", "정보처리기사 필기 (2027~)", "SQLD"),
                plan.goals().stream().map(g -> g.certificationName()).toList());
        assertTrue(plan.goals().stream().allMatch(g -> g.shortfallMinutes() == 0
                && g.projectedCompletionDate().isBefore(g.examDate())));
        assertTrue(plan.days().stream().allMatch(d -> d.allocatedMinutes() <= 120
                && d.date().getDayOfWeek().getValue() <= 5));
        // 세 자격증이 같은 주에 섞여 진행된다 (하나를 끝낸 뒤 다음으로 넘어가는 방식이 아님)
        assertEquals(3, plan.days().stream().filter(d -> d.date().isBefore(today.plusDays(14)))
                .flatMap(d -> d.allocations().stream()).map(a -> a.goalKey()).distinct().count());
        String summary = ReviewBasedPlannerController.summarize(plan, List.of(ipe, sqld, adsp));
        assertTrue(summary.contains("ADsP / 시작일"));
        assertTrue(summary.contains("데이터분석: 잠정 26.2시간 × 이해도 1.0 = 26.2시간"));
    }

    @Test
    void 목록에_없는_자격증이나_과목_누락은_거절한다() {
        GoalCatalog goal = legacySqld(MajorType.MAJOR);
        LocalDate exam = LocalDate.of(2027, 3, 6);
        PlanRequest unknown = new PlanRequest(120, List.of(new GoalInput("db-9-WRITTEN", "SQLD", exam,
                List.of(new SubjectInput("데이터 모델링의 이해", 1.0, 2, 0, 0)), null)));
        assertThrows(IllegalArgumentException.class,
                () -> ReviewBasedPlannerController.withServerHours(unknown, List.of(goal)));
        PlanRequest missing = new PlanRequest(120, List.of(new GoalInput("db-2-WRITTEN", "SQLD", exam,
                List.of(new SubjectInput("데이터 모델링의 이해", 1.0, 2, 0, 0)), null)));
        assertThrows(IllegalArgumentException.class,
                () -> ReviewBasedPlannerController.withServerHours(missing, List.of(goal)));
    }
}
