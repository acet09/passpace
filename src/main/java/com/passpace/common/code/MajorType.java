package com.passpace.common.code;

/**
 * [공통 계약] 전공 구분. DB에는 name()(영문 대문자)으로 저장하고, 화면에는 label 을 보여 준다.
 * 사용 컬럼: USERS.major_type, PASS_REVIEWS.major_type
 */
public enum MajorType {
    MAJOR("전공"),
    RELATED("유사전공"),
    NON_MAJOR("비전공");

    private final String label;

    MajorType(String label) {
        this.label = label;
    }

    public String getLabel() {
        return label;
    }

    /** DB 문자열 → Enum. null·빈 값·모르는 값이면 null */
    public static MajorType fromCode(String code) {
        if (code == null || code.isBlank()) {
            return null;
        }
        for (MajorType t : values()) {
            if (t.name().equalsIgnoreCase(code.trim())) {
                return t;
            }
        }
        return null;
    }
}
