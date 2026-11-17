package com.passpace.dto.collect;

import java.util.List;

/**
 * [용성·11-14] 시험일정 2순위 수동 크롤링 결과 (POST /admin/collect/manual/dataq-schedule)
 *
 * @param saved        새로 넣은 회차 수 (source_id NULL)
 * @param updated      날짜가 바뀌어 고친 회차 수 (source_id 는 그대로, EXAM_SCHEDULE_CHANGE_LOGS 기록)
 * @param unchanged    바뀐 것 없는 회차 수
 * @param unregistered CERTIFICATIONS 에 자격증 행이 없어 건너뛴 회차 수 (ADSP 는 db/09 실행 필요)
 * @param rounds       읽은 회차 요약 ("SQLD 제63회 시험 2026-11-14" 등)
 */
public record ManualScheduleResult(String status, int saved, int updated, int unchanged, int unregistered, int failed,
                                   List<String> rounds, String message) {
}
