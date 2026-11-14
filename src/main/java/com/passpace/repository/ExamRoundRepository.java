package com.passpace.repository;

import com.passpace.dto.collect.CollectDtos.ExamScheduleItem;

import java.time.LocalDate;
import java.util.Optional;

/** [용성] EXAM_ROUNDS, EXAM_SCHEDULE_CHANGE_LOGS 쓰기 */
public interface ExamRoundRepository {

    Optional<Long> findCertificationId(String examCode);

    /** 같은 회차(자격증·연도·회차·필기/실기)의 저장된 값 */
    Optional<StoredRound> find(long certificationId, int year, int roundNo, String examType);

    void insert(long certificationId, long sourceId, String examCode, ExamScheduleItem item);

    void update(long examRoundId, long sourceId, ExamScheduleItem item);

    void touch(long examRoundId);

    void insertChangeLog(long examRoundId, Long syncLogId, StoredRound before, ExamScheduleItem after, String changedFieldsJson);

    /** 비교용 저장 값 */
    record StoredRound(long examRoundId, LocalDate regStart, LocalDate regEnd,
                       LocalDate examStart, LocalDate examEnd, LocalDate resultDate) {
    }
}
