package com.passpace.collect;

/**
 * [용성] DATA_SOURCES 에 미리 넣어 둔 출처 번호 (db/03_seed.sql 과 같아야 한다).
 */
public final class CollectSources {

    /** 국가자격 시험일정 조회 API(15074408) */
    public static final long EXAM_SCHEDULE_API = 1L;
    /** 샘플 시험일정 (API 키가 없을 때) */
    public static final long SAMPLE_SCHEDULE = 2L;
    /** velog 합격·불합격 후기 */
    public static final long VELOG_REVIEW = 3L;
    /** 티스토리 합격·불합격 후기 (permission_checked_at 이 채워져야 수집됨) */
    public static final long TISTORY_REVIEW = 7L;
    /** SQLD 시험일정 공공데이터 API (한국데이터산업진흥원_데이터 자격검정 시험 정보 15062838) */
    public static final long SQLD_SCHEDULE_API = 8L;
    /** 소수 공개 사례 기반 참고 학습시간 잠정값 (03_seed.sql DATA_SOURCES 6) */
    public static final long PROVISIONAL_REFERENCE = 6L;

    private CollectSources() {
    }
}
