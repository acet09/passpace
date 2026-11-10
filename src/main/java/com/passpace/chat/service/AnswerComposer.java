package com.passpace.chat.service;

import com.passpace.chat.client.OllamaClient;
import com.passpace.chat.client.OllamaUnavailableException;
import com.passpace.chat.dto.ChatDtos.ComposedAnswer;
import com.passpace.chat.dto.ChatDtos.Evidence;
import com.passpace.chat.dto.ChatDtos.PhasePlan;
import com.passpace.chat.dto.ChatDtos.PlanNumbers;
import com.passpace.chat.dto.ChatDtos.StatsSummary;
import com.passpace.chat.dto.ChatDtos.SubjectPlan;
import com.passpace.common.code.ExamType;
import com.passpace.common.code.MajorType;
import com.passpace.common.code.StudyMethod;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [동건] 처리 ④ 답변 생성 + ⑤ 숫자 검증
 *  - Java 가 계산한 값과 통계, 근거 후기를 사람이 읽는 텍스트(자료)로 만들어 LLM 에 보낸다
 *  - LLM 답변의 숫자가 자료에 없는 숫자면 1회 다시 요청 → 그래도 실패하면 Java 기본 안내로 대체
 *  - Ollama 가 꺼져 있어도 Java 기본 안내로 답한다 (챗봇이 멈추지 않게)
 */
@Component
public class AnswerComposer {

    private static final Logger log = LoggerFactory.getLogger(AnswerComposer.class);
    private static final Pattern CITE = Pattern.compile("\\[근거\\s*(\\d+)]");

    private final OllamaClient ollama;
    private final NumberGuard numberGuard = new NumberGuard();
    private final String systemPrompt;

    public AnswerComposer(OllamaClient ollama) throws IOException {
        this.ollama = ollama;
        this.systemPrompt = new ClassPathResource("prompts/chat_answer_system.txt").getContentAsString(StandardCharsets.UTF_8);
    }

    /** 답변 생성에 필요한 모든 값 */
    public record AnswerContext(String question, LocalDate today, ExamType examType, MajorType majorType,
                                LocalDate examDate, String examDateNote, PlanNumbers plan, StatsSummary stats,
                                int minSample, String passCriteria) {
    }

    public ComposedAnswer compose(AnswerContext ctx) {
        String payload = buildPayload(ctx);
        Set<String> allowed = numberGuard.allowedNumbers(payload);
        String notice = statsNotice(ctx);
        try {
            String answer = ollama.chat(systemPrompt, payload, null, 0.2);
            Set<String> violations = numberGuard.findViolations(answer, allowed);
            if (!violations.isEmpty()) {
                log.warn("LLM 자료에 없는 숫자 {} - 재요청", violations);
                answer = ollama.chat(systemPrompt,
                        payload + "\n[수정 요구] 기존 답변에는 근거에 없는 숫자가 있었습니다: " +
                                String.join(", ", violations) +
                                ". 위 [자료]에 있는 숫자만 쓰고, 없는 숫자를 사용하지 마세요.", null, 0.1);
                violations = numberGuard.findViolations(answer, allowed);
            }
            if (violations.isEmpty())
                return new ComposedAnswer(answer, true, citedSources(answer, ctx.stats()), notice);
            log.warn("LLM 답변에 자료에 없는 숫자 {} - 기본 안내로 대체", violations);
            return new ComposedAnswer(templateAnswer(ctx), false, allSources(ctx.stats()),
                    "LLM 답변에 자료로 확인되지 않은 숫자가 있어 기본 안내로 대체했습니다." +
                            (notice == null ? "" : " " + notice));
        } catch (OllamaUnavailableException e) {
            return new ComposedAnswer(templateAnswer(ctx), false, allSources(ctx.stats()),
                    "LLM 을 사용할 수 없어 기본 안내로 답변했습니다. (" + e.getMessage() + ")" +
                            (notice == null ? "" : " " + notice));
        }
    }

    // Java 에서 산출한 값만 LLM 에 근거로 보낸다.
    String buildPayload(AnswerContext c) {
        StringBuilder sb = new StringBuilder();
        sb.append("[사용자 조건]\n")
                .append("오늘: ").append(c.today()).append("\n")
                .append("전공 구분: ").append(c.majorType() == null ? "미확인" : c.majorType().getLabel()).append("\n")
                .append("시험 구분: ").append(c.examType().getLabel()).append("\n")
                .append("시험일: ").append(c.examDate()).append("\n")
                .append("남은 일수: ").append(c.plan().remainingDays()).append("일\n")
                .append("하루 가용 시간: ").append(hm(c.plan().dailyMinutes())).append("\n");
        if (c.examDateNote() != null && !c.examDateNote().isBlank())
            sb.append("시험일 출처: ").append(c.examDateNote()).append("\n");
        sb.append("\n[시험 기본 정보]\n")
                .append(c.passCriteria() == null ? "합격 기준 확인되지 않음" : c.passCriteria()).append("\n");
        sb.append("\n[비슷한 분들과 비교]\n");
        if (!c.stats().available()) {
            sb.append("통계 미사용: 합격 후기의 유효 일일학습시간 표본 부족 (필요 ")
                    .append(c.minSample()).append("건, 확보 ").append(c.stats().sampleSize()).append("건).\n");
        } else {
            StatsSummary s = c.stats();
            sb.append("조건: ").append(s.conditionLabel()).append("\n")
                    .append("합격자 하루 학습시간 유효 표본: ").append(s.sampleSize()).append("건\n")
                    .append("합격자 하루 평균: ").append(hm(s.avgDailyMinutes())).append("\n")
                    .append("중앙값: ").append(hm(s.medianDailyMinutes())).append("\n")
                    .append("최소~최대: ").append(hm(s.minDailyMinutes())).append(" ~ ").append(hm(s.maxDailyMinutes())).append("\n")
                    .append("합격자 평균 전체 공부시간: ").append(s.avgTotalHours() == null ? "자료 없음" : s.avgTotalHours() + "시간").append("\n")
                    .append("합격자 평균 준비기간: ").append(s.avgPrepDays() == null ? "자료 없음" : s.avgPrepDays() + "일").append("\n")
                    .append("대표 학습 방식: ").append(s.topMethodCode() == null ? "확인되지 않음"
                            : StudyMethod.fromCode(s.topMethodCode()) == null ? s.topMethodCode()
                            : StudyMethod.fromCode(s.topMethodCode()).getLabel()).append("\n");
        }
        sb.append("\n[단계별 계획]\n")
                .append("총 학습 가능 시간: ").append(num(c.plan().totalHours())).append("시간\n")
                .append("총 주 수: ").append(c.plan().weeks()).append("주\n");
        for (PhasePlan phase : c.plan().phases())
            sb.append(phase.rangeLabel()).append(" ").append(phase.name())
                    .append(" (").append(phase.percent()).append("%, ").append(phase.days()).append("일, ")
                    .append(num(phase.hours())).append("시간): ").append(phase.focus()).append("\n");
        sb.append("\n[과목별 시간 배분]\n");
        for (SubjectPlan subject : c.plan().subjects())
            sb.append(subject.subjectName()).append(": ").append(num(subject.hours())).append("시간")
                    .append(subject.familiarity() == null ? "" : " (이해도 " + subject.familiarity() + "단계)")
                    .append("\n");
        if (c.stats().available()) {
            sb.append("\n[근거 후기] (샘플 데이터인 경우 실제 통계가 아님)\n");
            for (Evidence evidence : c.stats().evidences()) {
                sb.append("[근거 ").append(evidence.no()).append("] ").append(evidence.text()).append("\n");
            }
        }
        sb.append("\n[질문]\n").append(c.question());
        return sb.toString();
    }

    // Ollama 연결 실패나 숫자 검증 실패 시에도 Java 값으로 답한다.
    String templateAnswer(AnswerContext c) {
        StringBuilder sb = new StringBuilder();
        if (!c.stats().available()) sb.append("통계 미사용: 유효 합격 후기 표본이 부족합니다.\n\n");
        sb.append("■ 한 줄 요약\n")
                .append(c.examType().getLabel()).append(" 시험일(").append(c.examDate())
                .append(")까지 ").append(c.plan().remainingDays()).append("일 남았습니다. 하루 ")
                .append(hmShort(c.plan().dailyMinutes())).append(" 기준 총 ")
                .append(num(c.plan().totalHours())).append("시간을 학습할 수 있습니다.\n\n")
                .append("■ 비슷한 분들과 비교\n");
        if (c.stats().available()) {
            sb.append(c.stats().conditionLabel()).append("의 합격 후기 ").append(c.stats().sampleSize())
                    .append("건 기준 하루 평균 ").append(hmShort(c.stats().avgDailyMinutes()))
                    .append(", 중앙값 ").append(hmShort(c.stats().medianDailyMinutes()))
                    .append("입니다. 이 값은 합격을 보장하는 기준이 아닙니다.\n\n");
        } else sb.append("유효 표본이 ").append(c.minSample()).append("건 미만이므로 비교 통계를 사용하지 않습니다.\n\n");
        sb.append("■ 주차별 계획\n");
        for (PhasePlan phase : c.plan().phases())
            sb.append("- ").append(phase.rangeLabel()).append(": ").append(phase.name()).append(" · ")
                    .append(phase.focus()).append(" (").append(num(phase.hours())).append("시간)\n");
        sb.append("\n■ 과목별 우선순위와 공부 방법\n");
        if (c.plan().subjects().isEmpty()) sb.append("- 과목 정보가 없어 과목별 시간 배분을 생략했습니다.\n");
        else for (SubjectPlan sub : c.plan().subjects())
            sb.append("- ").append(sub.subjectName()).append(": ").append(num(sub.hours()))
                    .append("시간, 취약 개념 정리 후 관련 기출로 복습\n");
        sb.append("\n■ 주의할 점\n")
                .append("실제 시험 일정과 합격 기준은 공식 공고에서 확인하고, 학습 기록에 따라 계획을 조정하세요.");
        if (c.passCriteria() != null) sb.append("\n참고 합격 기준: ").append(c.passCriteria());
        return sb.toString();
    }

    private String statsNotice(AnswerContext c) {
        return !c.stats().available() ? "통계 미사용: 유효 합격 후기 표본 " +
                c.stats().sampleSize() + "건 (필요 " + c.minSample() + "건)" : null;
    }

    /** 사용된 [근거 n] 출처만 제공한다. */
    private List<String> citedSources(String answer, StatsSummary s) {
        if (s == null || !s.available()) return List.of();
        LinkedHashSet<String> urls = new LinkedHashSet<>();
        Matcher matcher = CITE.matcher(answer);
        while (matcher.find() && urls.size() < 3) {
            int no = Integer.parseInt(matcher.group(1));
            s.evidences().stream().filter(e -> e.no() == no && e.url() != null && !e.url().isBlank())
                    .map(Evidence::url).findFirst().ifPresent(urls::add);
        }
        return new ArrayList<>(urls);
    }

    private List<String> allSources(StatsSummary s) {
        if (s == null || !s.available()) return List.of();
        return s.evidences().stream().map(Evidence::url).filter(u -> u != null && !u.isBlank())
                .distinct().limit(3).toList();
    }

    static String hm(Integer minutes) {
        if (minutes == null) return "자료 없음";
        int h = minutes / 60, m = minutes % 60;
        if (h == 0) return minutes + "분";
        return h + "시간" + (m == 0 ? "" : " " + m + "분") + "(" + minutes + "분)";
    }

    static String hmShort(Integer minutes) {
        if (minutes == null) return "자료 없음";
        int h = minutes / 60, m = minutes % 60;
        if (h == 0) return minutes + "분";
        return h + "시간" + (m == 0 ? "" : " " + m + "분");
    }

    static String num(double v) {
        return java.math.BigDecimal.valueOf(v).stripTrailingZeros().toPlainString();
    }
}
