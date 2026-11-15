package com.passpace.controller;

import com.passpace.service.MultiGoalPlanCalculator;
import com.passpace.service.MultiGoalPlanCalculator.GoalInput;
import com.passpace.service.MultiGoalPlanCalculator.PlanRequest;
import com.passpace.service.MultiGoalPlanCalculator.SubjectInput;
import com.passpace.service.StudyHoursEvidence;
import com.passpace.service.ProvisionalExamSchedule;
import com.passpace.repository.ChatRepository;
import com.passpace.service.MultiGoalPlanCalculator.PlanResponse;
import com.passpace.error.ErrorCode;
import com.passpace.error.exception.ChatException;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.util.ResponseUtil;
import com.passpace.domain.UserStudyProfile;
import com.passpace.repository.UserStudyProfileQuery;
import com.passpace.constant.MajorType;
import com.passpace.service.StudyHoursByMajor;
import com.passpace.service.StudyHoursByMajor.Qualification;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * [동건] DB/기존 계약을 바꾸지 않는 통합 플래너 미리보기 API.
 * 과목명과 임시 기준시간은 서버의 근거 레지스트리로 결정한다.
 * 브라우저가 보낸 baseHours는 신뢰하지 않고 서버 값으로 교체한다.
 *
 * [JWT] 로그인 확인·전공 구분을 세션 대신 토큰(JwtPrincipal)에서 읽는다.
 *  - 토큰이 없으면 JwtFilter 가 먼저 401 → 메서드 안의 "로그인했나?" 검사가 필요 없어졌다
 *  - 실패는 ChatException / IllegalArgumentException 을 던지면 GlobalExceptionHandler 가
 *    {"status":"ERROR","code":400,"data":{"code":"...","detail":"이유"}} 로 바꿔 준다
 */
@RestController
@RequestMapping("/api/chat/planner")
public class MultiGoalPlannerController {

    public record SubjectCatalog(Long subjectId, String name, Double baseHours,
                                 boolean hasReferenceHours, String referenceType,
                                 double directlyRecordedHours, int directAuthorCount,
                                 int matchingSyllabusAuthors, String derivation,
                                 int majorGroupSubjectAuthors, int majorGroupSameSyllabusAuthors) { }
    public record GoalCatalog(String key, String certificationName, String examType,
                              boolean temporaryCatalog, List<SubjectCatalog> subjects,
                              StudyHoursEvidence.CertificateEstimate evidence,
                              StudyHoursByMajor.GroupBaseline majorEvidence,
                              LocalDate suggestedExamDate, String scheduleNotice, String scheduleBasisUrl) { }
    public record CatalogResponse(List<GoalCatalog> goals, List<String> notices,
                                  String loginMajor, String loginMajorLabel,
                                  Integer profileDailyMinutes, String dailyTimeSource) { }
    public record ChatPlanPreviewRequest(PlanRequest plan, Long conId) { }
    public record ChatPlanPreviewResponse(PlanResponse plan, String answer) { }

    /** 한 번에 묶어 계획할 수 있는 자격증 수 (같은 자격증의 필기·실기는 1개) */
    public static final int MAX_CERTIFICATIONS = 3;

    /** 플래너가 아는 자격증. demoCode 는 DB 에 자격증 행이 없을 때 쓰는 키("demo-{demoCode}-{시험구분}")의 일부. */
    private enum Cert {
        IPE("IPE"), SQLD("SQLD"), ADSP("ADSP"), CA1("CA1");

        final String demoCode;

        Cert(String demoCode) {
            this.demoCode = demoCode;
        }

        /** CERTIFICATIONS 한 행이 어느 자격증인가. 코드(source_exam_code)가 우선이고 이름은 보조. 모르면 null */
        static Cert of(String name, String sourceCode) {
            String n = name == null ? "" : name;
            String upper = n.toUpperCase(java.util.Locale.ROOT);
            if ("1320".equals(sourceCode) || "정보처리기사".equals(n)) return IPE;
            if ("SQLD".equals(sourceCode) || upper.contains("SQLD") || n.contains("SQL 개발자")) return SQLD;
            if ("ADSP".equals(sourceCode) || upper.contains("ADSP") || n.contains("데이터분석 준전문가")) return ADSP;
            if ("CA1".equals(sourceCode) || n.replace(" ", "").contains("컴퓨터활용능력1급")) return CA1;
            return null;
        }
    }

    /**
     * 카탈로그 한 줄 (자격증 × 시험구분).
     * temporaryInDatabase: DB 에 자격증이 있어도 과목 목록을 DB 가 아닌 내부 목록으로 쓰는 경우 (정처기 2027 필기).
     * name 은 브라우저 저장값·계획 이름에 쓰이므로 바꾸지 않는다.
     */
    private record GoalSpec(Cert cert, String name, String examType, Qualification qualification,
                            boolean temporaryInDatabase) { }

    private static final List<GoalSpec> SPECS = List.of(
            new GoalSpec(Cert.SQLD, "SQLD", "WRITTEN", Qualification.SQLD, false),
            new GoalSpec(Cert.IPE, "정보처리기사 필기 (2027~)", "WRITTEN", Qualification.IP_WRITTEN_2027, true),
            new GoalSpec(Cert.IPE, "정보처리기사 실기", "PRACTICAL", Qualification.IP_PRACTICAL, false),
            new GoalSpec(Cert.ADSP, "ADsP", "WRITTEN", Qualification.ADSP, false),
            new GoalSpec(Cert.CA1, "컴퓨터활용능력 1급 필기", "WRITTEN", Qualification.CA1_WRITTEN, false),
            new GoalSpec(Cert.CA1, "컴퓨터활용능력 1급 실기", "PRACTICAL", Qualification.CA1_PRACTICAL, false));

    private final JdbcTemplate jdbc;
    private final UserStudyProfileQuery profileQuery;
    private final ChatRepository chatRepository;
    private final MultiGoalPlanCalculator calculator = new MultiGoalPlanCalculator();

    @Autowired
    public MultiGoalPlannerController(JdbcTemplate jdbc, UserStudyProfileQuery profileQuery,
                                      ChatRepository chatRepository) {
        this.jdbc = jdbc;
        this.profileQuery = profileQuery;
        this.chatRepository = chatRepository;
    }

    /** 기존 테스트와의 호환 생성자. Spring에서는 @Autowired 생성자를 사용한다. */
    public MultiGoalPlannerController(JdbcTemplate jdbc) {
        this(jdbc, id -> java.util.Optional.empty(), null);
    }

    @GetMapping("/catalog")
    public ResponseEntity<?> catalog(@AuthenticationPrincipal JwtPrincipal loginUser) {
        MajorType major = requireMajor(loginUser);
        List<GoalCatalog> goals = new ArrayList<>();
        List<Map<String, Object>> certs = jdbc.queryForList("""
                SELECT certification_id, cert_name, source_exam_code
                FROM CERTIFICATIONS WHERE active_yn = 'Y' ORDER BY certification_id
                """);
        // DB 에 등록된 자격증은 "db-{ID}-{시험구분}", 아직 없는 자격증은 "demo-…" 키의 내부 목록으로 제공한다.
        Set<Cert> found = new HashSet<>();
        for (Map<String, Object> cert : certs) {
            long id = ((Number) cert.get("certification_id")).longValue();
            Cert kind = Cert.of((String) cert.get("cert_name"), (String) cert.get("source_exam_code"));
            if (kind == null || !found.add(kind)) continue;
            for (GoalSpec spec : SPECS) {
                if (spec.cert() != kind) continue;
                // 정처기 필기: 초기 DB의 필기 과목은 2026년 구 5과목. 2027년 새 4과목의 ID로 혼용하지 않는다.
                boolean useDbSubjects = !spec.temporaryInDatabase();
                goals.add(referenceGoal("db-" + id + "-" + spec.examType(), spec.name(), spec.examType(),
                        spec.temporaryInDatabase(), useDbSubjects ? id : null,
                        StudyHoursByMajor.resolve(spec.qualification(), major), useDbSubjects));
            }
        }
        for (GoalSpec spec : SPECS) {
            if (found.contains(spec.cert())) continue;
            goals.add(referenceGoal("demo-" + spec.cert().demoCode + "-" + spec.examType(), spec.name(),
                    spec.examType(), true, null, StudyHoursByMajor.resolve(spec.qualification(), major), false));
        }
        boolean foundSqlD = found.contains(Cert.SQLD);
        Integer profileDailyMinutes = null;
        String dailyTimeSource = "미설정";
        if (loginUser != null) {
            try {
                List<Integer> stored = jdbc.query("""
                        SELECT daily_minutes FROM USER_GOALS
                        WHERE user_id = ? AND daily_minutes BETWEEN 30 AND 960
                        ORDER BY created_at DESC, goal_id DESC LIMIT 1
                        """, (rs, rowNum) -> rs.getInt(1), loginUser.getUserId());
                if (stored != null && !stored.isEmpty()) {
                    profileDailyMinutes = stored.get(0);
                    dailyTimeSource = "USER_GOALS DB 저장값";
                }
            } catch (org.springframework.dao.DataAccessException ignored) {
                // 팀 통합 전에 확장 컬럼이 누락된 경우: 공통 프로필 계약의 값을 이용한다.
            }
            if (profileDailyMinutes == null) {
                UserStudyProfile profile = profileQuery.findByUserId(loginUser.getUserId()).orElse(null);
                if (profile != null && profile.dailyMinutes() != null && profile.dailyMinutes() >= 30
                        && profile.dailyMinutes() <= 960) {
                    profileDailyMinutes = profile.dailyMinutes();
                    dailyTimeSource = "학습 프로필(단독 데모에서는 150분 고정 대역값)";
                }
            }
        }
        return ResponseUtil.SUCCESS(new CatalogResponse(List.copyOf(goals), List.of(
                "정보처리기사 2027년 필기 4과목·실기 1과목, SQLD 2과목, ADsP 3과목, " +
                        "컴퓨터활용능력 1급 필기 3과목·실기 2과목을 지원합니다.",
                "한 번에 자격증 " + MAX_CERTIFICATIONS + "개까지 묶어 계획할 수 있습니다 " +
                        "(같은 자격증의 필기·실기는 1개로 셉니다). 묶은 자격증은 하루 공부시간을 함께 씁니다.",
                "전공 여부는 로그인 정보(토큰)의 " + major.getLabel() + " 설정을 사용하며, 사용자가 요청으로 변경할 수 없습니다.",
                "과목별 전공·비전공 통계는 분리 관리합니다. 표본 없는 집단은 50명 평균 대신 출처가 명시된 대체 계산값을 사용합니다.",
                "사전 이해도 1.3/1.0/0.7은 사용자가 과목별로 직접 선택해야 합니다.",
                "2027 정처기 새 과목의 실측 표본은 0명입니다. 기존 2026 후기를 개편 과목에 " +
                        "대응한 결과는 검증된 평균으로 표시하지 않습니다.",
                foundSqlD ? "SQLD는 DB 등록 과목과 대조합니다." :
                        "SQLD는 아직 DB 미등록이므로 공식 과목명을 내부 목록으로 제공합니다. DB 변경 없음."
                ), major.name(), major.getLabel(), profileDailyMinutes, dailyTimeSource));
    }

    private GoalCatalog referenceGoal(String key, String name, String examType, boolean temporary,
                                      Long certId, StudyHoursByMajor.GroupBaseline byMajor,
                                      boolean matchDatabaseSubjectIds) {
        StudyHoursEvidence.CertificateEstimate estimate = byMajor.reference();
        Map<String, Long> ids = new HashMap<>();
        if (certId != null && matchDatabaseSubjectIds) {
            jdbc.query("""
                    SELECT certification_subject_id, subject_name
                    FROM CERTIFICATION_SUBJECTS
                    WHERE certification_id = ? AND exam_type = ?
                    """, rs -> {
                        ids.put(normalize(rs.getString("subject_name")),
                                rs.getLong("certification_subject_id"));
                    }, certId, examType);
        }
        Qualification qualification = qualificationFor(name);
        List<SubjectCatalog> subjects = estimate.subjects().stream().map(sub ->
                new SubjectCatalog(ids.get(normalize(sub.name())), sub.name(), sub.hours(),
                        true, sub.referenceType(), sub.directlyRecordedHours(),
                        sub.directAuthorCount(), sub.matchingSyllabusAuthors(), sub.derivation(),
                        StudyHoursByMajor.subjectAuthors(qualification, byMajor.userMajor(), sub.name(), false),
                        StudyHoursByMajor.subjectAuthors(qualification, byMajor.userMajor(), sub.name(), true)))
                .toList();
        ProvisionalExamSchedule.Suggestion suggestion =
                ProvisionalExamSchedule.forGoal(name, LocalDate.now());
        // 상시시험(컴활)은 가상 목표일 없이 안내만 한다 → 사용자가 날짜를 직접 넣는다
        if (suggestion == null) suggestion = ProvisionalExamSchedule.anytimeExam(name);
        return new GoalCatalog(key, name, examType, temporary, subjects, estimate, byMajor,
                suggestion == null ? null : suggestion.targetDate(),
                suggestion == null ? "공식 일정 또는 개인 목표일 직접 확인 필요" : suggestion.notice(),
                suggestion == null ? "" : suggestion.basisUrl());
    }

    /** 클라이언트 숫자 변조를 막고 등록된 과목 목록/순서만 계산에 반영한다. */
    @PostMapping("/preview")
    public ResponseEntity<?> preview(@RequestBody PlanRequest plan,
                                     @AuthenticationPrincipal JwtPrincipal loginUser) {
        MajorType major = requireMajor(loginUser);
        try {
            return ResponseUtil.SUCCESS(calculator.calculate(standardizeServerHours(plan, major), LocalDate.now()));
        } catch (ArithmeticException e) {
            // 계산 중 숫자 범위 초과 등 → 사용자 입력 문제로 보고 400
            throw new ChatException(ErrorCode.INVALID_REQUEST, e.getMessage());
        }
    }


    /** 일반 채팅에서 바로 계산한 계획을 기존 대화방에도 저장한다. */
    @PostMapping("/preview-chat")
    public ResponseEntity<?> previewChat(@RequestBody ChatPlanPreviewRequest body,
                                         @AuthenticationPrincipal JwtPrincipal loginUser) {
        MajorType major = requireMajor(loginUser);
        if (body == null || body.conId() == null)
            throw new ChatException(ErrorCode.INVALID_REQUEST, "대화방 ID가 없습니다.");
        // "본인 대화방인가"는 주소 규칙(SecurityConfig)으로 알 수 없어서 DB 를 보고 여기서 검사한다 (강의안 p.9)
        if (!chatRepository.isOwner(body.conId(), loginUser.getUserId()))
            throw new ChatException(ErrorCode.FORBIDDEN_ACCESS, "본인 대화방만 수정할 수 있습니다.");
        try {
            PlanResponse result = calculator.calculate(standardizeServerHours(body.plan(), major), LocalDate.now());
            String answer = summarizePlan(result);
            chatRepository.insertMessage(body.conId(), "assistant", answer);
            return ResponseUtil.SUCCESS(new ChatPlanPreviewResponse(result, answer));
        } catch (ArithmeticException e) {
            throw new ChatException(ErrorCode.INVALID_REQUEST, e.getMessage());
        }
    }

    private static String summarizePlan(PlanResponse result) {
        StringBuilder sb = new StringBuilder("다중 자격증 자동 학습계획 (Java 계산)\n");
        sb.append("하루 총 ").append(result.dailyMinutes()).append("분 / 남은 학습량 ")
                .append(String.format(java.util.Locale.ROOT, "%.1f", result.totalRemainingMinutes() / 60.0))
                .append("시간\n");
        for (var goal : result.goals()) {
            sb.append(goal.certificationName()).append(" / 시작일 ").append(goal.startDate())
                    .append(" / 목표일 ").append(goal.examDate())
                    .append(" / 남은 ")
                    .append(String.format(java.util.Locale.ROOT, "%.1f", goal.remainingMinutes() / 60.0))
                    .append("시간\n");
        }
        if (!result.feasible()) sb.append("현재 가능시간으로 모두 완료하기 어려워 일정 조정이 필요합니다.\n");
        sb.append("2027년 목표일은 2026년 공고의 월/일을 옮긴 가상 날짜이며 공식 시험일이 아닙니다. ")
          .append("과목별 기준시간도 소수 후기 기반 잠정 추정치입니다.");
        return sb.toString();
    }

    private PlanRequest standardizeServerHours(PlanRequest request, MajorType major) {
        if (request == null || request.goals() == null)
            throw new IllegalArgumentException("계획할 자격증이 없습니다.");
        requireCertificationLimit(request.goals());
        List<GoalInput> acceptedGoals = new ArrayList<>();
        for (GoalInput goal : request.goals()) {
            if (goal == null || goal.certificationName() == null || goal.subjects() == null)
                throw new IllegalArgumentException("자격증 및 과목 입력이 올바르지 않습니다.");
            StudyHoursEvidence.CertificateEstimate estimate = estimateFor(goal, major).reference();
            Map<String, SubjectInput> given = new HashMap<>();
            for (SubjectInput s : goal.subjects()) {
                if (s == null || s.name() == null ||
                        given.putIfAbsent(normalize(s.name()), s) != null)
                    throw new IllegalArgumentException("과목이 없거나 중복되었습니다.");
            }
            if (given.size() != estimate.subjects().size())
                throw new IllegalArgumentException(goal.certificationName() + ": 과목 수가 출제기준과 다릅니다.");
            List<SubjectInput> accepted = new ArrayList<>();
            for (StudyHoursEvidence.SubjectEstimate s : estimate.subjects()) {
                SubjectInput selected = given.get(normalize(s.name()));
                if (selected == null)
                    throw new IllegalArgumentException("공식 과목 누락: " + s.name());
                accepted.add(new SubjectInput(s.name(), s.hours(), selected.familiarity(),
                        selected.progressPercent(), selected.actualMinutes()));
            }
            if (goal.certificationName().startsWith("정보처리기사 필기") && goal.examDate() != null &&
                    goal.examDate().isBefore(LocalDate.of(2027, 1, 1)))
                throw new IllegalArgumentException("2027년 4과목 목록은 2027년 이후 필기 시험에만 적용합니다.");
            acceptedGoals.add(new GoalInput(goal.key(), goal.certificationName(), goal.examDate(),
                    List.copyOf(accepted), goal.startDate()));
        }
        return new PlanRequest(request.dailyMinutes(), List.copyOf(acceptedGoals), request.studyWeekdays());
    }

    private StudyHoursByMajor.GroupBaseline estimateFor(GoalInput goal, MajorType major) {
        String name = goal.certificationName();
        for (GoalSpec spec : SPECS) {
            if (spec.name().equals(name) && goal.key() != null && goal.key().endsWith("-" + spec.examType()))
                return StudyHoursByMajor.resolve(spec.qualification(), major);
        }
        throw new IllegalArgumentException("현재 지원하지 않는 자격증·시험 구분입니다: " + name);
    }

    private Qualification qualificationFor(String name) {
        for (GoalSpec spec : SPECS) {
            if (spec.name().equals(name)) return spec.qualification();
        }
        throw new IllegalArgumentException("지원하지 않는 시험 분류입니다: " + name);
    }

    /**
     * 한 번에 묶는 자격증 수 제한. 목표 키("db-3-WRITTEN", "db-3-PRACTICAL")에서 시험구분을 뗀 값이
     * 같으면 같은 자격증이다 → 컴활 필기+실기는 1개로 센다.
     */
    public static void requireCertificationLimit(List<GoalInput> goals) {
        Set<String> certifications = new HashSet<>();
        for (GoalInput goal : goals) {
            if (goal == null || goal.key() == null) continue;   // 빈 값은 뒤의 검증에서 거절한다
            certifications.add(goal.key().replaceFirst("-(WRITTEN|PRACTICAL)$", ""));
        }
        if (certifications.size() > MAX_CERTIFICATIONS)
            throw new IllegalArgumentException("한 번에 계획할 수 있는 자격증은 최대 " + MAX_CERTIFICATIONS
                    + "개입니다 (같은 자격증의 필기·실기는 1개로 셉니다). 선택을 줄여 주세요.");
    }

    private static String normalize(String name) {
        return name == null ? "" : name.replaceAll("\\s+", "").trim();
    }
    /**
     * 토큰에 담긴 전공 구분. 없으면 400 MISSING_MAJOR.
     * (loginUser 가 null 인 경우는 JwtFilter 가 먼저 401 로 막으므로 실제로는 오지 않는다 — 테스트용 방어)
     */
    private MajorType requireMajor(JwtPrincipal loginUser) {
        if (loginUser == null) throw new ChatException(ErrorCode.FAILURE_JWT_VERIFIED);
        if (loginUser.getMajorType() == null) throw new ChatException(ErrorCode.MISSING_MAJOR);
        return loginUser.getMajorType();
    }
}
