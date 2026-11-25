package com.passpace.schedule;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.passpace.constant.MajorType;
import com.passpace.error.ErrorCode;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.schedule.PlanScheduleDtos.ScheduleException;
import com.passpace.schedule.WholePlanDtos.*;
import com.passpace.schedule.WholePlanRepository.Item;
import com.passpace.schedule.WholePlanRepository.Placement;
import com.passpace.schedule.WholePlanRepository.Plan;
import com.passpace.schedule.WholePlanRepository.Topic;
import com.passpace.service.MultiGoalPlanCalculator;
import com.passpace.study.StudyRepository;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.*;

/** [한결] 전체 일정의 미리보기 및 잠금·버전 검증 후 반영. */
@Service
public class WholePlanService {
    private static final ZoneId SEOUL = ZoneId.of("Asia/Seoul");
    private static final int DAILY_LIMIT = 960;
    private static final int WINDOW_DAYS = 540;
    private final StudyRepository users;
    private final WholePlanRepository plans;
    private final ObjectMapper json;
    private final Clock clock;

    @Autowired
    public WholePlanService(StudyRepository users, WholePlanRepository plans, ObjectMapper json,
                            ObjectProvider<Clock> clocks) {
        this(users, plans, json, clocks.getIfAvailable(Clock::systemUTC));
    }

    WholePlanService(StudyRepository users, WholePlanRepository plans, ObjectMapper json, Clock clock) {
        this.users = users;
        this.plans = plans;
        this.json = json;
        this.clock = clock;
    }

    private record SubjectBudget(long key, Topic topic, int minutes) {}
    private record State(Plan plan, LocalDate today, Map<Integer, Integer> caps,
                         List<Item> movable, List<Item> preserved, List<SubjectBudget> subjects) {}
    private record ChangeSet(LocalDate start, LocalDate end, Map<Integer, Integer> caps,
                             List<Item> removed, List<Placement> added, boolean changed) {}

    @Transactional(readOnly = true)
    public Editor editor(JwtPrincipal member, long planId) {
        long userId = memberId(member, false);
        var state = load(userId, planId, false);
        var p = state.plan();
        return new Editor(planId, p.name(), p.version(), p.start(), p.end(), state.today(), state.caps(),
                state.subjects().stream().map(s ->
                        new Subject(s.key(), s.topic().exam(), s.topic().name(), s.minutes())).toList(),
                state.preserved().size());
    }

    @Transactional(readOnly = true)
    public Preview preview(JwtPrincipal member, long planId, Edit edit) {
        long userId = memberId(member, false);
        var state = load(userId, planId, false);
        var change = prepare(state, edit);
        return new Preview(approval(userId, planId, state, change), change.changed(), state.preserved().size(),
                change.removed().stream().map(i -> allocation(i.topic(), i.date(), i.minutes())).toList(),
                change.added().stream().map(i -> allocation(i.topic(), i.date(), i.minutes())).toList());
    }

    @Transactional
    public Applied apply(JwtPrincipal member, long planId, Edit edit) {
        long userId = memberId(member, true);
        if (edit == null || edit.approval() == null || !edit.approval().matches("[0-9a-f]{64}")) {
            throw invalid("변경안을 미리 확인해 주세요.");
        }
        var state = load(userId, planId, true);
        ChangeSet change;
        try {
            change = prepare(state, edit);
        } catch (ScheduleException e) {
            if (e.getErrorCode() == ErrorCode.INVALID_REQUEST) {
                throw conflict("승인할 변경안이 달라졌어요. 미리보기를 다시 확인해 주세요.");
            }
            throw e;
        }
        if (!approval(userId, planId, state, change).equals(edit.approval())) {
            throw conflict("계획이나 학습기록이 바뀌었어요. 미리보기를 다시 확인해 주세요.");
        }
        if (!change.changed()) throw invalid("변경할 내용을 입력해 주세요.");
        var p = state.plan();
        plans.apply(userId, planId, p, planName(p.name(), change.caps()), change.start(), change.end(),
                jsonValue(change.caps()), change.removed(), change.added());
        return new Applied(planId, Math.addExact(p.version(), 1), change.start(), change.end());
    }

    private State load(long userId, long planId, boolean lock) {
        if (planId < 1) throw invalid("수정할 계획을 확인해 주세요.");
        var plan = plans.plan(userId, planId, lock).orElseThrow(() ->
                new ScheduleException(ErrorCode.NOT_FOUND_ENDPOINT, "사용 중인 학습계획을 찾을 수 없어요."));
        var today = LocalDate.now(clock.withZone(SEOUL));
        if (plan.start() == null || plan.end() == null || plan.version() < 1) {
            throw conflict("이 계획의 저장 정보가 부족해 전체 일정 수정이 어려워요.");
        }
        List<Item> movable = new ArrayList<>();
        List<Item> preserved = new ArrayList<>();
        Map<Topic, SubjectBudget> subjects = new LinkedHashMap<>();
        for (var item : plans.items(userId, planId)) {
            boolean protectedItem = item.protectedOn(today);
            (protectedItem ? preserved : movable).add(item);
            if (item.topic().name() == null || item.topic().name().isBlank()) continue;
            var old = subjects.get(item.topic());
            subjects.put(item.topic(), new SubjectBudget(old == null ? item.id() : old.key(), item.topic(),
                    (old == null ? 0 : old.minutes()) + (protectedItem ? 0 : item.minutes())));
        }
        return new State(plan, today, readCaps(plan.weekdayJson()), movable, preserved,
                List.copyOf(subjects.values()));
    }

    private Map<Integer, Integer> readCaps(String text) {
        if (text == null || text.isBlank()) return Map.of();
        try {
            var caps = json.readValue(text, new TypeReference<TreeMap<Integer, Integer>>() {});
            return caps != null && validCaps(caps) ? caps : Map.of();
        } catch (JsonProcessingException ignored) {
            return Map.of();
        }
    }

    private static ChangeSet prepare(State state, Edit edit) {
        if (edit == null || edit.expectedPlanVersion() == null) throw invalid("계획 버전을 확인해 주세요.");
        if (edit.expectedPlanVersion() != state.plan().version()) {
            throw conflict("계획이 바뀌었어요. 최신 일정을 다시 불러와 주세요.");
        }
        var start = edit.startDate();
        var end = edit.endDate();
        var today = state.today();
        var limit = today.plusDays(WINDOW_DAYS);
        if (start == null || end == null || end.isBefore(start) || end.isBefore(today)
                || outside(start, state.plan().start(), today, limit)
                || outside(end, state.plan().end(), today, limit)) {
            throw invalid("계획 기간을 확인해 주세요. 새 날짜는 오늘부터 540일 이내로 선택해 주세요.");
        }
        if (!validCaps(edit.weekdayMinutes())) throw invalid("공부할 요일마다 최대 1~960분을 입력해 주세요.");
        var caps = new TreeMap<>(edit.weekdayMinutes());
        if (state.preserved().stream().map(Item::date).filter(Objects::nonNull)
                .anyMatch(date -> date.isBefore(start) || date.isAfter(end))) {
            throw invalid("계획 기간에 지난 일정, 공부한 항목, 옮겨 둔 학습의 날짜가 모두 포함되어야 해요.");
        }
        var budgets = budgets(state.subjects(), edit.subjects());
        boolean sameBudgets = state.subjects().stream().allMatch(s -> budgets.get(s.key()) == s.minutes());
        if (start.equals(state.plan().start()) && end.equals(state.plan().end())
                && caps.equals(state.caps()) && sameBudgets) {
            return new ChangeSet(start, end, caps, List.of(), List.of(), false);
        }
        if (state.preserved().isEmpty() && budgets.values().stream().allMatch(minutes -> minutes == 0)) {
            throw invalid("학습을 배정할 과목을 하나 이상 남겨 주세요.");
        }

        List<Placement> placements = reschedule(state, start, end, caps, budgets);
        Map<Placement, Deque<Item>> existing = new LinkedHashMap<>();
        for (var item : state.movable()) {
            var placement = new Placement(item.topic(), item.date(), item.minutes());
            existing.computeIfAbsent(placement, key -> new ArrayDeque<>()).addLast(item);
        }
        var added = new ArrayList<Placement>();
        for (var placement : placements) {
            var matches = existing.get(placement);
            if (matches == null || matches.isEmpty()) added.add(placement);
            else matches.removeFirst();
        }
        var removed = existing.values().stream().flatMap(Collection::stream).toList();
        return new ChangeSet(start, end, caps, removed, added, true);
    }

    private static List<Placement> reschedule(State state, LocalDate start, LocalDate end,
                                               Map<Integer, Integer> caps, Map<Long, Integer> budgets) {
        Map<LocalDate, Integer> fixedMinutes = new HashMap<>();
        for (var item : state.preserved()) {
            if (item.date() != null && item.minutes() > 0) fixedMinutes.merge(item.date(), item.minutes(), Integer::sum);
        }
        var placements = new ArrayList<Placement>();
        var remaining = new LinkedHashMap<>(budgets);
        var queue = new ArrayDeque<>(state.subjects().stream().filter(s -> remaining.get(s.key()) > 0).toList());
        var first = start.isAfter(state.today()) ? start : state.today();
        for (var day = first; !day.isAfter(end) && !queue.isEmpty(); day = day.plusDays(1)) {
            int capacity = caps.getOrDefault(day.getDayOfWeek().getValue(), 0) - fixedMinutes.getOrDefault(day, 0);
            for (int count = queue.size(); count > 0 && capacity > 0; count--) {
                var subject = queue.removeFirst();
                int planned = Math.min(capacity, remaining.get(subject.key()));
                placements.add(new Placement(subject.topic(), day, planned));
                capacity -= planned;
                if (remaining.compute(subject.key(), (key, minutes) -> minutes - planned) > 0) queue.addLast(subject);
            }
        }
        if (!queue.isEmpty()) {
            long missing = remaining.values().stream().mapToLong(Integer::longValue).sum();
            throw invalid("배정할 시간이 " + missing + "분 부족해요. 기간·요일·가용 시간을 조정하거나 과목별 배정 시간을 줄여 주세요.");
        }
        return placements;
    }

    private static Map<Long, Integer> budgets(List<SubjectBudget> subjects, List<SubjectTime> requested) {
        var allowed = new HashSet<>(subjects.stream().map(SubjectBudget::key).toList());
        if (requested == null || requested.size() != allowed.size()) throw invalid("모든 과목의 시간을 입력해 주세요.");
        var result = new HashMap<Long, Integer>();
        for (var input : requested) {
            if (input == null || !allowed.remove(input.key()) || input.minutes() == null
                    || input.minutes() < 0 || input.minutes() > (WINDOW_DAYS + 1) * DAILY_LIMIT) {
                throw invalid("과목별 배정 시간을 확인해 주세요.");
            }
            result.put(input.key(), input.minutes());
        }
        return result;
    }

    private static boolean validCaps(Map<Integer, Integer> caps) {
        return caps != null && !caps.isEmpty() && caps.size() <= 7 && caps.entrySet().stream()
                .allMatch(e -> e.getKey() != null && e.getKey() >= 1 && e.getKey() <= 7
                        && e.getValue() != null && e.getValue() >= 1 && e.getValue() <= DAILY_LIMIT);
    }

    private static boolean outside(LocalDate value, LocalDate original, LocalDate today, LocalDate limit) {
        return !value.equals(original) && (value.isBefore(today) || value.isAfter(limit));
    }

    private static Allocation allocation(Topic topic, LocalDate date, int minutes) {
        return new Allocation(date, topic.exam(), topic.name(), minutes);
    }

    private static String planName(String existing, Map<Integer, Integer> caps) {
        if (existing == null) return "학습계획";
        int separator = existing.lastIndexOf(", ");
        if (!existing.startsWith("챗봇 학습계획 (") || separator < 0 || !existing.endsWith(")")) return existing;
        String time = caps.values().stream().distinct().count() == 1
                ? "하루 " + caps.values().iterator().next() + "분"
                : MultiGoalPlanCalculator.weekdayMinutesLabel(caps);
        String updated = existing.substring(0, separator) + ", " + time + ")";
        return updated.substring(0, Math.min(updated.length(), 200));
    }

    private String approval(long userId, long planId, State state, ChangeSet change) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(
                    json.writeValueAsBytes(List.of(userId, planId, state.plan().version(), state.today(),
                            state.preserved(), change))));
        } catch (NoSuchAlgorithmException | JsonProcessingException e) {
            throw new IllegalStateException("일정 미리보기 결과를 확인할 수 없어요.", e);
        }
    }

    private String jsonValue(Object value) {
        try {
            return json.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("요일별 설정을 저장할 수 없어요.", e);
        }
    }

    private long memberId(JwtPrincipal member, boolean lock) {
        if (member == null || member.getUserId() == null || member.getUserId() < 1) {
            throw new ScheduleException(ErrorCode.FAILURE_JWT_VERIFIED, "다시 로그인해 주세요.");
        }
        long userId = member.getUserId();
        var user = users.findUser(userId, lock).orElseThrow(() ->
                new ScheduleException(ErrorCode.FAILURE_JWT_VERIFIED, "다시 로그인해 주세요."));
        if (member.getMajorType() == null || MajorType.fromCode(user.majorCode()) != member.getMajorType()) {
            throw new ScheduleException(ErrorCode.FORBIDDEN_ACCESS, "회원정보가 바뀌었어요. 다시 로그인해 주세요.");
        }
        return userId;
    }

    private static ScheduleException invalid(String text) {
        return new ScheduleException(ErrorCode.INVALID_REQUEST, text);
    }

    private static ScheduleException conflict(String text) {
        return new ScheduleException(ErrorCode.DATA_INTEGRITY_VIOLATION, text);
    }
}
