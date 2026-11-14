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
