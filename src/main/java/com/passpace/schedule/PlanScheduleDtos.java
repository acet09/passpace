package com.passpace.schedule;

import com.fasterxml.jackson.annotation.JsonAnySetter;
import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
import com.passpace.error.ErrorCode;
import com.passpace.error.exception.BaseAppException;
import com.passpace.study.StudyDtos.StrictDateDeserializer;
import com.passpace.study.StudyDtos.StrictIntegerDeserializer;

import java.time.LocalDate;

public final class PlanScheduleDtos {
    private PlanScheduleDtos() {}

    public record Change(
            @JsonDeserialize(using = StrictIntegerDeserializer.class) Integer expectedPlanVersion,
            @JsonDeserialize(using = StrictDateDeserializer.class) LocalDate scheduledDate,
            @JsonDeserialize(using = StrictIntegerDeserializer.class) Integer estimatedMinutes) {
        @JsonAnySetter
        public void unknown(String name, Object value) {
            throw new IllegalArgumentException("지원하지 않는 계획 수정 항목입니다.");
        }
    }

    public record Updated(long planId, long taskId, int planVersion,
                          LocalDate scheduledDate, int estimatedMinutes) {}

    public record Period(
            @JsonDeserialize(using = StrictIntegerDeserializer.class) Integer expectedPlanVersion,
            @JsonDeserialize(using = StrictDateDeserializer.class) LocalDate startDate,
            @JsonDeserialize(using = StrictDateDeserializer.class) LocalDate endDate) {
        @JsonAnySetter
        public void unknown(String name, Object value) {
            throw new IllegalArgumentException("지원하지 않는 계획 기간 항목입니다.");
        }
    }

    public record PeriodUpdated(long planId, int planVersion, LocalDate startDate, LocalDate endDate) {}

    static final class ScheduleException extends BaseAppException {
        ScheduleException(ErrorCode code, String detail) {
            super(code, detail);
        }
    }
}
