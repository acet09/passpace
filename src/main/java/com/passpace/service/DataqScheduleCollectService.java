package com.passpace.service;

import com.passpace.client.DataqScheduleClient;
import com.passpace.client.DataqScheduleClient.DataqRound;
import com.passpace.dto.collect.CollectDtos.ExamScheduleItem;
import com.passpace.dto.collect.ManualScheduleResult;
import com.passpace.error.exception.CollectException;
import com.passpace.repository.ExamRoundRepository;
import com.passpace.repository.ExamRoundRepository.StoredRound;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.Optional;

/**
 * [용성·11-14] 시험일정 2순위: 관리자가 수동 수집 화면에서 직접 실행하는 dataq 일정 크롤링 (SQLD·ADsP)
 *  - 1순위(공공 API)가 실패해도 자동으로 여기로 넘어오지 않는다
 *  - 새 회차는 source_id NULL 로 저장 (DATA_SOURCES 행을 추가하지 않음 → 1순위 API 회차(8)와 구분됨)
 *  - 같은 회차가 있으면 날짜가 바뀐 경우만 고치고 EXAM_SCHEDULE_CHANGE_LOGS 에 남긴다. 이때 source_id 는 바꾸지 않는다
 *  - DATA_SYNC_JOBS 에는 기록하지 않는다 (source_id NOT NULL) → 결과는 응답으로 바로 보여 준다
 */
@Service
public class DataqScheduleCollectService {

    private static final Logger log = LoggerFactory.getLogger(DataqScheduleCollectService.class);

    private final DataqScheduleClient client;
    private final ExamRoundRepository examRoundRepository;

    public DataqScheduleCollectService(DataqScheduleClient client, ExamRoundRepository examRoundRepository) {
        this.client = client;
        this.examRoundRepository = examRoundRepository;
    }

    public synchronized ManualScheduleResult collect() {
        List<DataqRound> rounds;
        try {
            rounds = DataqScheduleClient.parse(client.fetch(), LocalDate.now().getYear());
        } catch (CollectException e) {
            return new ManualScheduleResult("FAILED", 0, 0, 0, 0, 0, List.of(), e.getFailType() + ": " + e.getMessage());
        }
        if (rounds.isEmpty()) {
            return new ManualScheduleResult("FAILED", 0, 0, 0, 0, 0, List.of(),
                    "일정표에서 회차를 찾지 못했습니다. 페이지 구조가 바뀌었는지 확인하세요 (기존 데이터는 그대로).");
        }
        int saved = 0, updated = 0, same = 0, unregistered = 0, failed = 0;
        List<String> lines = new ArrayList<>();
        for (DataqRound r : rounds) {
            ExamScheduleItem it = r.item();
            lines.add(it.description() + " · 접수 " + it.regStart() + "~" + it.regEnd() + " · 시험 " + it.examStart()
                    + " · 발표 " + it.resultDate());
            Optional<Long> certId = examRoundRepository.findCertificationId(r.code());
            if (certId.isEmpty()) {
                unregistered++;
                continue;
            }
            try {
                var stored = examRoundRepository.find(certId.get(), it.examYear(), it.roundNo(), it.examType().name());
                if (stored.isEmpty()) {
                    examRoundRepository.insertWithNullableSource(certId.get(), null, r.code(), it);
                    saved++;
                } else {
                    String changed = changedFields(stored.get(), it);
                    if (changed == null) {
                        examRoundRepository.touch(stored.get().examRoundId());
                        same++;
                    } else {
                        examRoundRepository.insertChangeLog(stored.get().examRoundId(), null, stored.get(), it, changed);
                        examRoundRepository.updateDatesOnly(stored.get().examRoundId(), it);
                        updated++;
                    }
                }
            } catch (Exception e) {
                failed++;
                log.warn("dataq 회차 저장 실패 {}: {}", it.description(), e.getMessage());
            }
        }
        String status = failed == 0 ? "SUCCESS" : (saved + updated > 0 ? "PARTIAL" : "FAILED");
        String msg = "dataq 일정 " + rounds.size() + "개 회차: 새로 저장 " + saved + ", 날짜 변경 " + updated + ", 변경 없음 " + same
                + (unregistered > 0 ? ", 자격증 미등록 " + unregistered + "(ADsP 는 db/09 실행 필요)" : "")
                + (failed > 0 ? ", 실패 " + failed : "");
        return new ManualScheduleResult(status, saved, updated, same, unregistered, failed, lines, msg);
    }

    private static String changedFields(StoredRound b, ExamScheduleItem a) {
        List<String> c = new ArrayList<>();
        if (!Objects.equals(b.regStart(), a.regStart())) c.add("\"reg_start_at\"");
        if (!Objects.equals(b.regEnd(), a.regEnd())) c.add("\"reg_end_at\"");
        if (!Objects.equals(b.examStart(), a.examStart())) c.add("\"exam_start_date\"");
        if (!Objects.equals(b.examEnd(), a.examEnd())) c.add("\"exam_end_date\"");
        if (!Objects.equals(b.resultDate(), a.resultDate())) c.add("\"result_date\"");
        return c.isEmpty() ? null : "[" + String.join(",", c) + "]";
    }
}
