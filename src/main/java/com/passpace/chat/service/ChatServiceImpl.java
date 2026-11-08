package com.passpace.chat.service;

import com.passpace.chat.dto.ChatDtos.ChatRequest;
import com.passpace.chat.dto.ChatDtos.ChatResponse;
import com.passpace.chat.dto.ChatDtos.ComposedAnswer;
import com.passpace.chat.dto.ChatDtos.ExtractedCondition;
import com.passpace.chat.dto.ChatDtos.PlanNumbers;
import com.passpace.chat.dto.ChatDtos.StatsSummary;
import com.passpace.chat.repository.ChatRepository;
import com.passpace.chat.service.AnswerComposer.AnswerContext;
import com.passpace.common.LoginUser;
import com.passpace.common.code.ExamType;
import com.passpace.common.code.MajorType;
import com.passpace.common.code.StudyMethod;
import com.passpace.common.profile.UserStudyProfile;
import com.passpace.common.profile.UserStudyProfileQuery;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

/**
 * [동건] 챗봇 전체 흐름 (기획안 5.3 연동 구조). 로그인 사용자만 들어온다 (컨트롤러에서 확인).
 *   ⓪ 대화방 준비 + 앞 질문 불러오기 → 이번 질문 저장
 *   ① 조건 추출 (이번 질문 정규식 → 앞 질문 → 단서가 있으면 LLM)
 *      학습 계획 질문이 아니면 계산하지 않고 안내만 한다 (과목을 물으면 DB 과목 목록)
 *   ② 빠진 값 채우기 (마이페이지 목표 → 가장 가까운 시험일) / 그래도 없으면 되묻기
 *   ③ Java 계산 (남은 일수, 총 가용시간, 단계, 과목별 시간)
 *   ④ 유사 집단 통계 (SQL 조회 + Java 계산, 표본 부족 시 조건 확대)
 *   ⑤ LLM 답변 생성 + 숫자 검증 (실패하면 Java 기본 안내)
 *   ⑥ 답변을 CHAT_MESSAGES 에 저장
 */
@Service
public class ChatServiceImpl implements ChatService {

    private static final int MAX_MESSAGE = 500;
    /** 조건을 이어 쓸 앞 질문 수 */
    private static final int HISTORY_LIMIT = 5;

    private final ConditionExtractor conditionExtractor;
    private final StatsAnalyzer statsAnalyzer;
    private final AnswerComposer answerComposer;
    private final ChatRepository chatRepository;
    private final UserStudyProfileQuery profileQuery;     // 공통 계약 (구현: 한결)
    private final PlanCalculator planCalculator = new PlanCalculator();
    private final RegexConditionParser intentParser = new RegexConditionParser();
    private final String examCode;

    public ChatServiceImpl(ConditionExtractor conditionExtractor, StatsAnalyzer statsAnalyzer,
                           AnswerComposer answerComposer, ChatRepository chatRepository,
                           UserStudyProfileQuery profileQuery,
                           @Value("${passpace.certification-code}") String examCode) {
        this.conditionExtractor = conditionExtractor;
        this.statsAnalyzer = statsAnalyzer;
        this.answerComposer = answerComposer;
        this.chatRepository = chatRepository;
        this.profileQuery = profileQuery;
        this.examCode = examCode;
    }

    @Override
    public ChatResponse answer(ChatRequest request, LoginUser loginUser) {
        if (request == null || request.message() == null || request.message().isBlank())
            throw new IllegalArgumentException("질문을 입력해 주세요.");
        String message = request.message().trim();
        if (message.length() > MAX_MESSAGE)
            throw new IllegalArgumentException("질문은 500자 이내로 입력해 주세요.");
        if (loginUser == null || loginUser.userId() == null)
            throw new IllegalArgumentException("로그인 사용자 정보가 없습니다.");
        long certId = chatRepository.findCertificationId(examCode)
                .orElseThrow(() -> new IllegalStateException("자격증 기준 데이터가 없습니다. 03_seed.sql 실행 여부를 확인하세요."));
        Long conId = request.conId();
        List<String> history;
        if (conId != null && chatRepository.isOwner(conId, loginUser.userId())) {
            history = chatRepository.findRecentUserMessages(conId, HISTORY_LIMIT);
        } else {
            conId = chatRepository.createConversation(loginUser.userId(),
                    message.length() <= 60 ? message : message.substring(0, 60));
            history = List.of();
        }
        chatRepository.insertMessage(conId, "user", message);

        LocalDate today = LocalDate.now();
        ExtractedCondition current = intentParser.parse(message, today);
        boolean isPlan = intentParser.isPlanQuestion(message, current);
        if (!isPlan && !history.isEmpty() && !message.contains("과목") &&
                (current.examType() != null || current.majorType() != null) &&
                (message.contains("요") || message.contains("그럼") || message.contains("이면"))) {
            isPlan = true; // "실기는요?" 와 같은 이어지는 계획 질문
        }
        // 종목을 제시하며 학습계획을 요청하면 Java 통합 플래너에서 계산하도록
        // 빠른 사전 이해도 선택을 연다. 이 경로는 Ollama 조건 추출을 호출하지 않는다.
        boolean certMention = mentionsSqlD(message) || message.contains("정처기")
                || message.contains("정보처리기사");
        boolean planMention = message.contains("계획") || message.contains("공부")
                || message.contains("준비") || message.contains("따고") || message.contains("따려")
                || message.contains("시간 분배") || message.contains("시간배분");
        if (certMention && planMention) {
            // 단독 데모의 StubUserStudyProfileQuery는 150분 고정 대역이다.
            // 실제 사용자가 선택하지 않은 시간을 '설정된 하루 시간'으로 안내하지 않는다.
            String text = "말씀하신 자격증의 학습계획을 계산할게요. "
                    + "2027년 시험일정이 확정되지 않은 경우 2026년 일정의 월/일을 옮긴 가상 목표일을 사용합니다. "
                    + "먼저 하루 전체 공부 가능시간을 직접 선택한 뒤, 과목별 사전 이해도를 클릭해 주세요. "
                    + "정처기와 SQLD는 선택한 하루 시간을 함께 사용하며 나머지 시간 배분은 Java가 계산합니다.";
            return reply(conId, text, "AUTO_PLAN_SETUP");
        }
        if (mentionsSqlD(message)) {
            return reply(conId, "SQLD는 데이터 모델링의 이해, SQL 기본 및 활용 2과목입니다. "
                    + "'SQLD 계획 세워줘'라고 입력하면 직접 계산할 수 있어요.", null);
        }
        // 단순 인사나 안내 요청에서는 느린 Ollama 조건 추출을 실행할 필요가 없다.
        if (!isPlan) return reply(conId, guideAnswer(message, current, certId), null);
        ExtractedCondition cond = conditionExtractor.extract(message, history, today);

        if (current.examDatePast())
            return reply(conId, "입력하신 시험일이 이미 지났습니다. 앞으로의 시험일을 다시 알려 주세요.", "지난 시험일");

        UserStudyProfile profile = profileQuery.findByUserId(loginUser.userId()).orElse(null);
        MajorType major = cond.majorType() != null ? cond.majorType()
                : loginUser.majorType() != null ? loginUser.majorType()
                : profile == null ? null : profile.majorType();
        ExamType examType = cond.examType() == null ? ExamType.WRITTEN : cond.examType();
        LocalDate examDate = cond.examDate();
        String dateNote = "질문에서 추출한 시험일";
        if (examDate == null && profile != null && profile.targetExamDate() != null
                && profile.targetExamDate().isAfter(today)) {
            examDate = profile.targetExamDate();
            dateNote = "마이페이지 목표 시험일";
        }
        if (examDate == null) {
            examDate = chatRepository.findNearestExamStart(certId, examType, today).orElse(null);
            dateNote = "DB에서 찾은 가장 가까운 시험일 (공식 공고 확인 필요)";
        }
        if (examDate == null)
            return reply(conId, "시험일을 알려 주세요. 예: '3월 20일 시험, 하루 2시간'.", "시험일 미확인");
        if (!examDate.isAfter(today))
            return reply(conId, "시험일까지 남은 기간이 없습니다. 오늘 이후의 시험일을 알려 주세요.", "시험일 확인 필요");
        Integer dailyMinutes = cond.dailyMinutes();
        if (dailyMinutes == null && profile != null) dailyMinutes = profile.dailyMinutes();
        if (dailyMinutes == null || dailyMinutes < 30 || dailyMinutes > 960)
            return reply(conId, "하루 공부 가능한 시간을 알려 주세요. 예: '하루 2시간 30분'.", "하루 학습시간 미확인");

        int remainingDays = (int) ChronoUnit.DAYS.between(today, examDate);
        StatsSummary stats = statsAnalyzer.analyze(certId, examType, major, remainingDays);
        StudyMethod method = stats.available() ? StudyMethod.fromCode(stats.topMethodCode()) : null;
        List<String> subjects = chatRepository.findSubjectNames(certId, examType);
        Map<String, Integer> familiarity = profile == null || profile.familiarityBySubject() == null
                ? Map.of() : profile.familiarityBySubject();
        PlanNumbers plan = planCalculator.calculate(today, examDate, dailyMinutes, subjects, familiarity, method);
        ComposedAnswer result = answerComposer.compose(new AnswerContext(message, today, examType,
                major, examDate, dateNote, plan, stats, statsAnalyzer.getMinSample(),
                chatRepository.findPassCriteria(certId).orElse(null)));
        chatRepository.insertMessage(conId, "assistant", result.text());
        return new ChatResponse(result.text(), conId, stats.sampleSize(), stats.available(),
                stats.conditionLabel(), result.sources(), result.notice(), result.llmUsed());
    }

    /** 계획이 아닌 인사/과목 질문은 DB 목록을 보여 주고 계획을 재계산하지 않는다. */
    private String guideAnswer(String message, ExtractedCondition cond, long certId) {
        if (message.contains("과목")) {
            ExamType type = cond.examType() == null ? ExamType.WRITTEN : cond.examType();
            List<String> names = chatRepository.findSubjectNames(certId, type);
            return names.isEmpty() ? type.getLabel() + " 과목 정보가 아직 등록되어 있지 않습니다."
                    : "정보처리기사 " + type.getLabel() + " 과목은 " + String.join(", ", names)
                    + "입니다. (현재 DB에 등록된 과목 기준)";
        }
        if (message.contains("고마") || message.contains("감사"))
            return "도움이 되었다니 다행입니다. 시험일이나 하루 공부시간을 변경하고 싶으면 이어서 말씀해 주세요.";
        return "정보처리기사 필기·실기 학습계획과 SQLD 통합 계획을 도와드릴 수 있어요. "
                + "복수 자격증은 '통합 학습계획' 탭에서 자격증별 시험일과 과목별 사전 이해도를 선택해 주세요. "
                + "단일 정보처리기사 계획은 시험일을 알려 주시면 학습 프로필의 하루 가능시간을 먼저 확인합니다.";
    }

    /** SQLD는 별도 자격증이며 정보처리기사 기본 종목코드로 계산하면 안 된다. */
    private static boolean mentionsSqlD(String message) {
        return message != null && message.toUpperCase(java.util.Locale.ROOT).contains("SQLD");
    }

    /** 현재 /api/chat 단일 종목 인터페이스는 유지하고, 복수 목표는 통합 플래너로 안내한다. */
    private static String multiGoalGuide(String message, UserStudyProfile profile) {
        boolean info = message.contains("정보처리기사") || message.contains("정처기");
        boolean written = message.contains("필기");
        String names = info ? "정보처리기사" + (written ? " 필기" : "") + "와 SQLD" : "SQLD";
        StringBuilder out = new StringBuilder("준비하려는 자격증은 ").append(names).append("로 이해했습니다. ");
        if (java.util.regex.Pattern.compile("(?:총|전체|합계)\\s*\\d+(?:\\.\\d+)?\\s*시간")
                .matcher(message).find()) {
            out.append("말씀한 '총 학습시간'은 하루 가능시간과 다른 값이며, 현재 통합 플래너는 하루 가능시간을 기준으로 계산하므로 이 총시간을 자동 배분하지는 않습니다. ");
        }
        Integer daily = profile == null ? null : profile.dailyMinutes();
        if (daily != null && daily >= 30 && daily <= 960) {
            out.append("현재 학습 프로필에서 하루 ").append(daily)
                    .append("분을 확인했습니다(단독 데모에서는 고정된 테스트 값일 수 있습니다). ");
        } else {
            out.append("학습 프로필에서 하루 공부시간을 확인하지 못했습니다. ");
        }
        out.append("오른쪽 '통합 학습계획' 탭에서 각 자격증의 시험일을 따로 지정하고, ")
                .append("과목별 사전 이해도(낮음·보통·높음)를 직접 선택해 주세요. ")
                .append("같은 날짜의 하루 공부시간은 두 자격증이 공유해 계산됩니다.");
        return out.toString();
    }

    /** 되묻기 및 안내 답변도 DB에 저장한다. */
    private ChatResponse reply(Long conId, String text, String notice) {
        chatRepository.insertMessage(conId, "assistant", text);
        return new ChatResponse(text, conId, 0, false, null, List.of(), notice, false);
    }
}
