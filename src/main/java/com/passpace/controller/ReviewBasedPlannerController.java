package com.passpace.controller;

import com.passpace.constant.ExamType;
import com.passpace.constant.MajorType;
import com.passpace.controller.MultiGoalPlannerController.CatalogResponse;
import com.passpace.controller.MultiGoalPlannerController.ChatPlanPreviewRequest;
import com.passpace.controller.MultiGoalPlannerController.ChatPlanPreviewResponse;
import com.passpace.controller.MultiGoalPlannerController.GoalCatalog;
import com.passpace.controller.MultiGoalPlannerController.SubjectCatalog;
import com.passpace.domain.StudyReference;
import com.passpace.domain.StudyReference.SubjectHours;
import com.passpace.dto.ResponseDto;
import com.passpace.error.ErrorCode;
import com.passpace.error.exception.ChatException;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.repository.ChatPlanStore;
import com.passpace.repository.ChatRepository;
import com.passpace.repository.StudyReferenceQuery;
import com.passpace.service.MultiGoalPlanCalculator;
import com.passpace.service.MultiGoalPlanCalculator.GoalInput;
import com.passpace.service.MultiGoalPlanCalculator.PlanRequest;
import com.passpace.service.MultiGoalPlanCalculator.PlanResponse;
import com.passpace.service.MultiGoalPlanCalculator.SubjectInput;
import com.passpace.service.StudyHoursByMajor;
import com.passpace.service.StudyHoursEvidence;
import com.passpace.util.ResponseUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [동건] 크롤링한 합격 후기를 근거로 과목별 평균 학습시간을 정하고 계획을 짜 주는 플래너 API.
 *
 * 기존 코드·DB 는 바꾸지 않고 이미 있는 것만 이어 붙인다.
 *   크롤링 → PASS_REVIEWS → (StudyReferenceAggregator) → STUDY_REFERENCE_STATS 의 VERIFIED 행
 *          → StudyReferenceQuery (용성 제공 계약) → 여기 → MultiGoalPlanCalculator
 *
 *  - 과목별 평균 학습시간 = 합격 후기 총 학습시간 평균 × 과목 비율 (StudyReferenceQuery 가 계산)
 *  - 후기 표본이 최소 표본(passpace.stats.min-sample)에 못 미치는 자격증은
 *    기존 플래너(MultiGoalPlannerController)의 값을 그대로 돌려준다 → 화면·계산이 예전과 같다
 *  - 응답 모양은 기존 /api/chat/planner/** 와 같다. 후기 기반 값이면 evidence.status 가 "REVIEW_VERIFIED"
 */
@RestController
@RequestMapping("/api/chat/planner/review-based")
public class ReviewBasedPlannerController {

    /** 후기 실측 평균이 적용된 자격증의 evidence.status */
    public static final String REVIEW_STATUS = "REVIEW_VERIFIED";

    private static final Logger log = LoggerFactory.getLogger(ReviewBasedPlannerController.class);
    private static final Pattern DB_KEY = Pattern.compile("db-(\\d+)-(WRITTEN|PRACTICAL)");

    private final MultiGoalPlannerController legacy;
    private final StudyReferenceQuery referenceQuery;
    private final ChatRepository chatRepository;
    private final ChatPlanStore planStore;
    private final MultiGoalPlanCalculator calculator = new MultiGoalPlanCalculator();

    public ReviewBasedPlannerController(MultiGoalPlannerController legacy, StudyReferenceQuery referenceQuery,
                                        ChatRepository chatRepository, ChatPlanStore planStore) {
        this.planStore = planStore;
        this.legacy = legacy;
        this.referenceQuery = referenceQuery;
        this.chatRepository = chatRepository;
    }

    @GetMapping("/catalog")
    public ResponseEntity<?> catalog(@AuthenticationPrincipal JwtPrincipal loginUser) {
        return ResponseUtil.SUCCESS(reviewBasedCatalog(loginUser));
    }

    /** 브라우저가 보낸 baseHours 는 믿지 않고, catalog 와 같은 서버 값으로 바꿔 계산한다. */
    @PostMapping("/preview")
    public ResponseEntity<?> preview(@RequestBody PlanRequest plan,
                                     @AuthenticationPrincipal JwtPrincipal loginUser) {
        CatalogResponse catalog = reviewBasedCatalog(loginUser);
        try {
            return ResponseUtil.SUCCESS(calculator.calculate(withServerHours(plan, catalog.goals()), LocalDate.now()));
        } catch (ArithmeticException e) {
            throw new ChatException(ErrorCode.INVALID_REQUEST, e.getMessage());
        }
    }

    /** 계산한 계획 요약을 대화방에도 남긴다. */
    @PostMapping("/preview-chat")
    public ResponseEntity<?> previewChat(@RequestBody ChatPlanPreviewRequest body,
                                         @AuthenticationPrincipal JwtPrincipal loginUser) {
        CatalogResponse catalog = reviewBasedCatalog(loginUser);
        if (body == null || body.conId() == null)
            throw new ChatException(ErrorCode.INVALID_REQUEST, "대화방 ID가 없습니다.");
        if (!chatRepository.isOwner(body.conId(), loginUser.getUserId()))
            throw new ChatException(ErrorCode.FORBIDDEN_ACCESS, "본인 대화방만 수정할 수 있습니다.");
        try {
            PlanResponse result = calculator.calculate(withServerHours(body.plan(), catalog.goals()), LocalDate.now());
            String answer = summarize(result, catalog.goals());
            chatRepository.insertMessage(body.conId(), "assistant", answer);
            return ResponseUtil.SUCCESS(new ChatPlanPreviewResponse(result, answer));
        } catch (ArithmeticException e) {
            throw new ChatException(ErrorCode.INVALID_REQUEST, e.getMessage());
        }
    }

    /** 마이페이지에 넣기: 브라우저가 보낸 결과를 믿지 않고 같은 요청으로 다시 계산해서 저장한다. */
    @PostMapping("/save")
    public ResponseEntity<?> save(@RequestBody PlanRequest plan,
                                  @AuthenticationPrincipal JwtPrincipal loginUser) {
        CatalogResponse catalog = reviewBasedCatalog(loginUser);
        PlanResponse result;
        try {
            result = calculator.calculate(withServerHours(plan, catalog.goals()), LocalDate.now());
        } catch (ArithmeticException e) {
            throw new ChatException(ErrorCode.INVALID_REQUEST, e.getMessage());
        }
        Map<String, Long> subjectIds = new HashMap<>();
        for (GoalCatalog g : catalog.goals())
            for (SubjectCatalog s : g.subjects())
                if (s.subjectId() != null) subjectIds.put(g.key() + "|" + s.name(), s.subjectId());
        long planId = planStore.replace(loginUser.getUserId(), result, subjectIds);
        return ResponseUtil.SUCCESS(Map.of("planId", planId, "days", result.days().size(),
                "totalMinutes", result.totalRemainingMinutes() - result.totalShortfallMinutes()));
    }

    /** 마이페이지 표시용: 저장된 챗봇 계획 (없으면 plan = null) */
    @GetMapping("/saved")
    public ResponseEntity<?> saved(@AuthenticationPrincipal JwtPrincipal loginUser) {
        Map<String, Object> body = new HashMap<>();
        body.put("plan", planStore.findActive(loginUser.getUserId()));
        return ResponseUtil.SUCCESS(body);
    }

    // ---------------------------------------------------------------------
    // 기존 카탈로그 + 후기 실측값 덮어쓰기
    // ---------------------------------------------------------------------

    private CatalogResponse reviewBasedCatalog(JwtPrincipal loginUser) {
        // 로그인·전공 확인, 과목 목록, 시험 목표일은 기존 플래너가 하던 대로 둔다
        CatalogResponse base = (CatalogResponse) ((ResponseDto<?>) legacy.catalog(loginUser).getBody()).getData();
        MajorType major = loginUser.getMajorType();
        List<GoalCatalog> goals = new ArrayList<>();
        int applied = 0;
        for (GoalCatalog goal : base.goals()) {
            GoalCatalog replaced = applyReference(goal, findReference(goal, major), major);
            if (replaced != goal) applied++;
            goals.add(replaced);
        }
        List<String> notices = new ArrayList<>();
        notices.add(applied == 0
                ? "크롤링한 합격 후기가 아직 최소 표본에 못 미쳐 모든 자격증에 잠정 기준시간을 사용합니다."
                : "과목별 기준시간: " + applied + "개 시험은 크롤링한 합격 후기의 실측 평균으로 계산했습니다. "
                + "나머지는 후기 표본이 부족해 잠정 기준시간을 사용합니다.");
        notices.addAll(base.notices());
        return new CatalogResponse(List.copyOf(goals), List.copyOf(notices), base.loginMajor(),
                base.loginMajorLabel(), base.profileDailyMinutes(), base.dailyTimeSource());
    }

    /** DB 에 등록된 자격증(key = db-{자격증ID}-{시험구분})만 후기 통계를 찾는다. 조회 실패는 "후기 없음"으로 본다. */
    private StudyReference findReference(GoalCatalog goal, MajorType major) {
        Matcher m = DB_KEY.matcher(goal.key() == null ? "" : goal.key());
        if (!m.matches()) return null;
        try {
            return referenceQuery.find(Long.parseLong(m.group(1)), ExamType.valueOf(m.group(2)), major).orElse(null);
        } catch (DataAccessException e) {
            log.warn("참고 학습시간 조회 실패 → 기존 잠정값 사용 ({}): {}", goal.key(), e.getMessage());
            return null;
        }
    }

    /**
     * 후기 실측 평균(VERIFIED)이 있으면 과목별 기준시간과 근거 설명을 그 값으로 바꾼 사본을 만든다.
     * 실측이 없거나 과목 목록이 서로 맞지 않으면 받은 goal 을 그대로 돌려준다 (Spring·DB 없이 테스트 가능).
     */
    static GoalCatalog applyReference(GoalCatalog goal, StudyReference ref, MajorType userMajor) {
        if (ref == null || !ref.verified() || ref.totalHours() <= 0 || ref.subjects() == null) return goal;
        Map<String, SubjectHours> measured = new HashMap<>();
        for (SubjectHours s : ref.subjects()) measured.put(normalize(s.subjectName()), s);
        if (measured.size() != goal.subjects().size()) return goal;
        for (SubjectCatalog s : goal.subjects()) {
            SubjectHours h = measured.get(normalize(s.name()));
            if (h == null || !(h.hours() > 0)) return goal;
        }

        int samples = ref.sampleCount();
        boolean sameGroup = ref.appliedMajor() != null && ref.appliedMajor() == userMajor;
        // 수집된 정보처리기사 필기 후기는 2026년 이전(5과목) 시험이다. 2027년 4과목의 직접 기록은 아니다.
        boolean olderSyllabus = goal.certificationName().startsWith("정보처리기사 필기");
        int sameSyllabus = olderSyllabus ? 0 : samples;
        String total = hoursText(ref.totalHours());
        String group = sameGroup ? userMajor.getLabel() + " 합격 후기" : "전공 구분 없는 전체 합격 후기";

        List<SubjectCatalog> subjects = new ArrayList<>();
        List<StudyHoursEvidence.SubjectEstimate> estimates = new ArrayList<>();
        for (SubjectCatalog s : goal.subjects()) {
            SubjectHours h = measured.get(normalize(s.name()));
            String type = "크롤링 합격 후기 " + samples + "건 실측 평균 × 과목 비율";
            String derivation = group + " " + samples + "건의 총 학습시간 평균 " + total + "시간 × 이 과목 비율 "
                    + Math.round(h.hours() / ref.totalHours() * 100) + "% = " + hoursText(h.hours()) + "시간. "
                    + (goal.subjects().size() == 1 ? "과목이 하나라 총 평균을 그대로 사용."
                    : "과목별 시간을 따로 적은 후기는 거의 없어 과목 비율은 잠정 비율(공개 학습일지 1건)을 사용.");
            subjects.add(new SubjectCatalog(h.subjectId(), s.name(), h.hours(), true, type, 0, samples,
                    sameSyllabus, derivation, sameGroup ? samples : 0, sameGroup ? sameSyllabus : 0));
            estimates.add(new StudyHoursEvidence.SubjectEstimate(s.name(), h.hours(), 0, samples,
                    sameSyllabus, type, derivation));
        }

        String range = ref.minHours() == null || ref.maxHours() == null ? ""
                : " 후기별 총 학습시간 범위는 " + hoursText(ref.minHours()) + "~" + hoursText(ref.maxHours()) + "시간으로 개인차가 큽니다.";
        String syllabusNote = olderSyllabus
                ? " 수집된 후기는 2026년 이전 5과목 시험 기준이며 2027년 4과목에 그대로 적용했습니다." : "";
        String method = (ref.sourceNote() == null ? "합격 후기 " + samples + "건 실측 평균" : ref.sourceNote())
                + (goal.subjects().size() == 1 ? "" : " → 과목별 시간 = 총 평균 × 과목 비율(잠정)");
        String warning = "총 학습시간은 크롤링한 합격 후기 " + samples + "건의 평균입니다."
                + (goal.subjects().size() == 1 ? "" : " 과목별 배분 비율은 아직 잠정값입니다.") + range + syllabusNote;
        StudyHoursEvidence.CertificateEstimate estimate = new StudyHoursEvidence.CertificateEstimate(
                goal.evidence() == null ? goal.certificationName() : goal.evidence().version(),
                method, warning, ref.totalHours(), samples, sameSyllabus, REVIEW_STATUS,
                List.of(), List.copyOf(estimates));

        String groupWarning = sameGroup
                ? userMajor.getLabel() + " 합격 후기 " + samples + "건의 실측 평균을 사용합니다." + syllabusNote
                : (userMajor == null ? "" : userMajor.getLabel() + " 합격 후기는 최소 표본에 못 미쳐 ")
                + "전공 구분 없는 전체 합격 후기 " + samples + "건의 평균을 사용합니다." + syllabusNote;
        StudyHoursByMajor.GroupBaseline baseline = new StudyHoursByMajor.GroupBaseline(
                userMajor, userMajor == null ? null : userMajor.getLabel(),
                ref.appliedMajor() == null ? "ALL" : ref.appliedMajor().name(),
                sameGroup ? samples : 0, sameGroup ? sameSyllabus : 0, sameGroup, !sameGroup,
                sameGroup ? "REVIEW_VERIFIED_SAME_GROUP" : "REVIEW_VERIFIED_ALL_MAJORS", groupWarning,
                goal.majorEvidence() == null ? null : goal.majorEvidence().groupCounts(), estimate);

        return new GoalCatalog(goal.key(), goal.certificationName(), goal.examType(), goal.temporaryCatalog(),
                List.copyOf(subjects), estimate, baseline, goal.suggestedExamDate(), goal.scheduleNotice(),
                goal.scheduleBasisUrl());
    }

    // ---------------------------------------------------------------------
    // 요청 검증 (기존 플래너와 같은 규칙) + 서버 기준시간으로 교체
    // ---------------------------------------------------------------------

    static PlanRequest withServerHours(PlanRequest request, List<GoalCatalog> catalog) {
        if (request == null || request.goals() == null)
            throw new IllegalArgumentException("계획할 자격증이 없습니다.");
        Map<String, GoalCatalog> byKey = new HashMap<>();
        for (GoalCatalog g : catalog) byKey.put(g.key(), g);
        List<GoalInput> acceptedGoals = new ArrayList<>();
        for (GoalInput goal : request.goals()) {
            if (goal == null || goal.certificationName() == null || goal.subjects() == null)
                throw new IllegalArgumentException("자격증 및 과목 입력이 올바르지 않습니다.");
            GoalCatalog known = byKey.get(goal.key());
            if (known == null || !known.certificationName().equals(goal.certificationName()))
                throw new IllegalArgumentException("현재 지원하지 않는 자격증·시험 구분입니다: " + goal.certificationName());
            Map<String, SubjectInput> given = new HashMap<>();
            for (SubjectInput s : goal.subjects()) {
                if (s == null || s.name() == null || given.putIfAbsent(normalize(s.name()), s) != null)
                    throw new IllegalArgumentException("과목이 없거나 중복되었습니다.");
            }
            if (given.size() != known.subjects().size())
                throw new IllegalArgumentException(goal.certificationName() + ": 과목 수가 출제기준과 다릅니다.");
            List<SubjectInput> accepted = new ArrayList<>();
            for (SubjectCatalog s : known.subjects()) {
                SubjectInput selected = given.get(normalize(s.name()));
                if (selected == null)
                    throw new IllegalArgumentException("공식 과목 누락: " + s.name());
                accepted.add(new SubjectInput(s.name(), s.baseHours(), selected.familiarity(),
                        selected.progressPercent(), selected.actualMinutes()));
            }
            // 날짜는 사용자가 자유롭게 정한다 (시험일이 아니어도 됨). 범위 검사는 계산기가 한다: 끝 날짜는 내일~540일 이내, 시작일은 끝 날짜 이전
            acceptedGoals.add(new GoalInput(goal.key(), goal.certificationName(), goal.examDate(),
                    List.copyOf(accepted), goal.startDate()));
        }
        return new PlanRequest(request.dailyMinutes(), List.copyOf(acceptedGoals), request.studyWeekdays());
    }

    static String summarize(PlanResponse result, List<GoalCatalog> catalog) {
        Map<String, GoalCatalog> byKey = new HashMap<>();
        for (GoalCatalog g : catalog) byKey.put(g.key(), g);
        StringBuilder sb = new StringBuilder("다중 자격증 자동 학습계획 (Java 계산)\n");
        sb.append("하루 총 ").append(result.dailyMinutes()).append("분 / 남은 학습량 ")
                .append(hoursText(result.totalRemainingMinutes() / 60.0)).append("시간\n");
        for (var goal : result.goals()) {
            GoalCatalog known = byKey.get(goal.key());
            boolean fromReviews = known != null && isReviewBased(known);
            sb.append(goal.certificationName()).append(" / 시작일 ").append(goal.startDate())
                    .append(" / 목표일 ").append(goal.examDate())
                    .append(" / 남은 ").append(hoursText(goal.remainingMinutes() / 60.0)).append("시간 / 기준시간: ")
                    .append(fromReviews
                            ? groupLabel(known) + " 합격 후기 " + known.evidence().baselineAuthors() + "건 실측 평균 "
                            + hoursText(known.evidence().referenceTotalHours()) + "시간"
                            : "소수 후기 기반 잠정 추정치")
                    .append("\n");
            // 과목별 평균 학습시간 × 이해도 가중치 = 계획에 넣은 시간
            for (var subject : goal.subjects()) {
                sb.append("  · ").append(subject.name()).append(": ")
                        .append(fromReviews ? "후기 평균 " : "잠정 ").append(hoursText(subject.baseHours()))
                        .append("시간 × 이해도 ").append(subject.weight()).append(" = ")
                        .append(hoursText(subject.remainingMinutes() / 60.0)).append("시간\n");
            }
        }
        if (!result.feasible()) sb.append("현재 가능시간으로 모두 완료하기 어려워 일정 조정이 필요합니다.\n");
        sb.append("2027년 목표일은 2026년 공고의 월/일을 옮긴 가상 날짜일 수 있으며 공식 시험일이 아닙니다. ")
                .append("과목별 시간은 총 평균을 잠정 과목 비율로 나눈 값입니다.");
        return sb.toString();
    }

    static boolean isReviewBased(GoalCatalog goal) {
        return goal.evidence() != null && REVIEW_STATUS.equals(goal.evidence().status());
    }

    /** 어느 집단의 후기 평균인가: 내 전공 집단이면 그 이름, 표본 부족으로 전체를 썼으면 "전공 구분 없는 전체" */
    private static String groupLabel(GoalCatalog goal) {
        var group = goal.majorEvidence();
        return group == null || group.fallback() || group.userMajorLabel() == null
                ? "전공 구분 없는 전체" : group.userMajorLabel();
    }

    private static String hoursText(double hours) {
        return String.format(Locale.ROOT, "%.1f", hours);
    }

    private static String normalize(String name) {
        return name == null ? "" : name.replaceAll("\\s+", "").trim();
    }
}
