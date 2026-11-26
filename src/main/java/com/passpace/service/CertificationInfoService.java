package com.passpace.service;

import com.passpace.constant.ExamType;
import com.passpace.dto.cert.CertificationViews.CertDetail;
import com.passpace.dto.cert.CertificationViews.CertSummary;
import com.passpace.dto.cert.CertificationViews.ExamInfo;
import com.passpace.dto.cert.CertificationViews.NextEvent;
import com.passpace.dto.cert.CertificationViews.Notes;
import com.passpace.dto.cert.CertificationViews.Round;
import com.passpace.repository.CertificationInfoQuery;
import com.passpace.repository.CertificationInfoQuery.CertRow;
import com.passpace.repository.CertificationInfoQuery.ExamInfoRow;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * [11-26] 지원 자격증 정보 메뉴 (앱 홈 "지원 자격증" 섹션 → 목록 → 상세).
 * DB 값을 모아 응답을 만들기만 한다. 값이 없으면 null 그대로 (지어내지 않음).
 */
@Service
public class CertificationInfoService {

    /** 최근 합격률은 3개 회차까지 */
    static final int PASS_RATE_LIMIT = 3;

    private final CertificationInfoQuery query;
    private final Clock clock;

    /** 생성자가 둘(테스트용 Clock)이라 Spring 이 쓸 생성자를 지정한다 */
    @Autowired
    public CertificationInfoService(CertificationInfoQuery query) {
        this(query, Clock.systemDefaultZone());
    }

    CertificationInfoService(CertificationInfoQuery query, Clock clock) {
        this.query = query;
        this.clock = clock;
    }

    /** 목록. category 는 분야(IT/데이터/사무·회계/안전), q 는 이름 검색 (둘 다 비우면 전체). 다음 일정이 가까운 순, 일정 없는 자격증은 뒤로 */
    public List<CertSummary> list(String category, String q) {
        LocalDate today = LocalDate.now(clock);
        Map<Long, List<Round>> rounds = query.findRoundsAll(today.getYear() - 1, today);
        Map<Long, List<String>> types = query.findExamTypes();
        String keyword = q == null ? "" : norm(q);
        return query.findActive().stream()
                .filter(r -> category == null || category.isBlank() || category.equals(r.category()))
                .filter(r -> keyword.isEmpty() || norm(r.name()).contains(keyword))
                .map(r -> summary(r, types.getOrDefault(r.certificationId(), List.of()),
                        rounds.getOrDefault(r.certificationId(), List.of()), today))
                .sorted(Comparator.comparing((CertSummary s) -> s.nextEvent() == null ? Long.MAX_VALUE : s.nextEvent().dDay())
                        .thenComparing(CertSummary::certificationId))
                .toList();
    }

    /** 상세. 없는 자격증이면 empty */
    public Optional<CertDetail> detail(long certificationId) {
        LocalDate today = LocalDate.now(clock);
        Optional<CertRow> found = query.findActive(certificationId);
        if (found.isEmpty()) return Optional.empty();
        CertRow r = found.get();

        List<Round> rounds = query.findRounds(certificationId, today.getYear(), today);
        Map<String, List<String>> subjects = query.findSubjects(certificationId);
        List<ExamInfoRow> infoRows = query.findExamInfos(certificationId);

        // 시험 구분: 시험 정보 행 + 과목 + 회차에 나오는 구분을 모두 (필기 → 실기 순)
        Set<String> typeSet = new LinkedHashSet<>();
        infoRows.forEach(e -> typeSet.add(e.examType().toUpperCase(Locale.ROOT)));
        typeSet.addAll(subjects.keySet());
        rounds.forEach(x -> { if (x.examType() != null) typeSet.add(x.examType()); });
        List<String> typeList = sortTypes(typeSet);

        List<ExamInfo> exams = new ArrayList<>();
        for (String type : typeList) {
            ExamInfoRow e = infoRows.stream().filter(x -> x.examType().equalsIgnoreCase(type)).findFirst().orElse(null);
            String criteria = e != null && e.passCriteria() != null ? e.passCriteria() : r.passCriteria();
            exams.add(new ExamInfo(type, label(type), e == null ? null : e.fee(), e == null ? null : e.questionCount(),
                    e == null ? null : e.durationMinutes(), e == null ? null : e.method(), criteria,
                    e == null ? null : e.scopeYear(), subjects.getOrDefault(type, List.of())));
        }

        Round nextExam = rounds.stream().filter(x -> !x.past()).findFirst().orElse(null);
        Notes notes = new Notes(r.writtenExemption(), r.requiredItems(), r.validity(), r.refundNote(), r.refundUrl(),
                r.resultNotice(), r.relatedCerts());
        return Optional.of(new CertDetail(summary(r, typeList, rounds, today), r.eligibility(), r.eligibilityCheckUrl(),
                r.officialUrl(), r.applyUrl(), r.infoVerifiedAt(), notes, exams, nextExam, rounds,
                query.findPassRates(certificationId, PASS_RATE_LIMIT)));
    }

    // ---------------------------------------------------------------------

    private static CertSummary summary(CertRow r, List<String> examTypes, List<Round> rounds, LocalDate today) {
        NextEvent next = r.alwaysOpen() ? null : nextEvent(rounds, today);
        return new CertSummary(r.certificationId(), r.name(), r.certType(), r.grade(), r.category(), r.issuingOrg(),
                r.summary(), examTypes, r.alwaysOpen(), next);
    }

    /** 오늘 이후 가장 가까운 일정 1개: 접수 중이면 마감일, 아니면 접수 시작·추가 접수·시험·발표 중 가장 빠른 날 */
    static NextEvent nextEvent(List<Round> rounds, LocalDate today) {
        NextEvent best = null;
        for (Round x : rounds) {
            List<NextEvent> c = new ArrayList<>();
            LocalDate regStart = day(x.regStartAt());
            LocalDate regEnd = day(x.regEndAt());
            if (regStart != null && regEnd != null && !today.isBefore(regStart) && !today.isAfter(regEnd)) {
                c.add(event("REG_OPEN", "원서 접수 마감", regEnd, today, x));
            } else if (regStart != null && regStart.isAfter(today)) {
                c.add(event("REG_START", "원서 접수 시작", regStart, today, x));
            }
            LocalDate addStart = day(x.addRegStartAt());
            if (addStart != null && addStart.isAfter(today)) c.add(event("ADD_REG", "추가 접수 시작", addStart, today, x));
            if (x.examStartDate() != null && !x.examStartDate().isBefore(today)) c.add(event("EXAM", "시험", x.examStartDate(), today, x));
            if (x.resultDate() != null && !x.resultDate().isBefore(today)) c.add(event("RESULT", "합격 발표", x.resultDate(), today, x));
            for (NextEvent e : c) {
                if (best == null || e.date().isBefore(best.date())) best = e;
            }
        }
        return best;
    }

    private static NextEvent event(String kind, String label, LocalDate date, LocalDate today, Round x) {
        String examLabel = x.examTypeLabel() == null ? "" : x.examTypeLabel() + " ";
        return new NextEvent(kind, examLabel + label, date, ChronoUnit.DAYS.between(today, date), x.examType(),
                x.examYear(), x.roundNo(), x.projected());
    }

    private static LocalDate day(LocalDateTime t) {
        return t == null ? null : t.toLocalDate();
    }

    private static List<String> sortTypes(Set<String> types) {
        return types.stream().filter(t -> ExamType.fromCode(t) != null)
                .sorted(Comparator.comparingInt(t -> ExamType.fromCode(t).ordinal())).toList();
    }

    private static String label(String examType) {
        ExamType t = ExamType.fromCode(examType);
        return t == null ? null : t.getLabel();
    }

    private static String norm(String s) {
        return s == null ? "" : s.replaceAll("\\s+", "").toLowerCase(Locale.ROOT);
    }
}
