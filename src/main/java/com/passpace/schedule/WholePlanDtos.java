package com.passpace.schedule;

import com.fasterxml.jackson.annotation.JsonAnySetter;
import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
import com.passpace.study.StudyDtos.StrictDateDeserializer;
import com.passpace.study.StudyDtos.StrictIntegerDeserializer;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/** [한결] 같은 계획 안에서 남은 일정 전체를 미리 보고 저장한다. */
public final class WholePlanDtos {
    private WholePlanDtos() {}

    public record Subject(long key, String exam, String name, int minutes) {}
    public record Editor(long planId, String planName, int planVersion, LocalDate startDate, LocalDate endDate,
                         LocalDate today, Map<Integer, Integer> weekdayMinutes, List<Subject> subjects,
                         int protectedTasks) {}

    public record SubjectTime(Long key,
            @JsonDeserialize(using = StrictIntegerDeserializer.class) Integer minutes) {}

    public record Edit(
            @JsonDeserialize(using = StrictIntegerDeserializer.class) Integer expectedPlanVersion,
            @JsonDeserialize(using = StrictDateDeserializer.class) LocalDate startDate,
            @JsonDeserialize(using = StrictDateDeserializer.class) LocalDate endDate,
            @JsonDeserialize(contentUsing = StrictIntegerDeserializer.class) Map<Integer, Integer> weekdayMinutes,
            List<SubjectTime> subjects,
            String approval) {
        @JsonAnySetter
        public void unknown(String name, Object value) {
            throw new IllegalArgumentException("지원하지 않는 전체 일정 수정 항목입니다.");
        }
    }

    public record Allocation(LocalDate date, String exam, String subject, int minutes) {}
    public record Preview(String approval, boolean changed, int protectedTasks,
                          List<Allocation> removed, List<Allocation> added) {}
    public record Applied(long planId, int planVersion, LocalDate startDate, LocalDate endDate) {}
}
