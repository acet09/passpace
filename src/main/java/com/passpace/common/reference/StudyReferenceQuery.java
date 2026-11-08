package com.passpace.common.reference;

import com.passpace.common.code.ExamType;
import com.passpace.common.code.MajorType;

import java.util.Optional;

/**
 * [공통 계약] 참고 학습시간 조회. 구현: 용성 (collect/stats/JdbcStudyReferenceQuery)
 *
 * 찾는 순서 (먼저 있는 것을 사용)
 *  1) 해당 전공 집단의 VERIFIED (합격 후기 실측)
 *  2) 전공 구분 없는 VERIFIED
 *  3) PROVISIONAL (소수 사례 잠정값)
 * 과목별 시간은 후기에 과목별 시간이 거의 없으므로, VERIFIED 총시간 × 잠정 과목 비율로 나눈다.
 */
public interface StudyReferenceQuery {

    /** 참고 학습시간. 데이터가 하나도 없으면 empty */
    Optional<StudyReference> find(long certificationId, ExamType examType, MajorType major);
}
