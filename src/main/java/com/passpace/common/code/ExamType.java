package com.passpace.common.code;

/**
 * [공통 계약] 시험 구분. 사용 컬럼: EXAM_ROUNDS.exam_type, CERTIFICATION_SUBJECTS.exam_type, PASS_REVIEWS.exam_type
 */
public enum ExamType {
    WRITTEN("필기"),
    PRACTICAL("실기");

    private final String label;

    ExamType(String label) {
        this.label = label;
    }

    public String getLabel() {
        return label;
    }

    public static ExamType fromCode(String code) {
        if (code == null || code.isBlank()) {
            return null;
        }
        for (ExamType t : values()) {
            if (t.name().equalsIgnoreCase(code.trim())) {
                return t;
            }
        }
        return null;
    }
}
