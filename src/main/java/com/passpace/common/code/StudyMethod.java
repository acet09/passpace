package com.passpace.common.code;

/**
 * [공통 계약] 학습 방식. 사용 컬럼: PASS_REVIEWS.study_method (확장 컬럼)
 */
public enum StudyMethod {
    THEORY("이론 위주"),
    PAST_EXAM("기출 위주"),
    BALANCED("이론·기출 병행");

    private final String label;

    StudyMethod(String label) {
        this.label = label;
    }

    public String getLabel() {
        return label;
    }

    public static StudyMethod fromCode(String code) {
        if (code == null || code.isBlank()) {
            return null;
        }
        for (StudyMethod m : values()) {
            if (m.name().equalsIgnoreCase(code.trim())) {
                return m;
            }
        }
        return null;
    }
}
