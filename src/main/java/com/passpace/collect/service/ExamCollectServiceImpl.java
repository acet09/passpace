package com.passpace.collect.service;

import com.passpace.collect.CollectSources;
import com.passpace.collect.client.CollectException;
import com.passpace.collect.client.DataGoKrExamClient;
import com.passpace.collect.dto.CollectDtos.CollectResult;
import com.passpace.collect.dto.CollectDtos.ExamScheduleItem;
import com.passpace.collect.repository.ExamRoundRepository;
import com.passpace.collect.repository.ExamRoundRepository.StoredRound;
import com.passpace.collect.repository.SyncJobRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

/**
 * [용성] 시험일정 수집 흐름
 *  1. DATA_SYNC_JOBS 에 시작 기록
 *  2. API 호출 (키가 없으면 샘플)
 *  3. 회차별로 새로 넣거나, 날짜가 바뀌었으면 변경 이력을 남기고 수정
 *  4. DATA_SYNC_JOBS 에 결과 기록
 *  ※ 시험일정 API 는 현재 연도만 제공한다 (정처기 시험정보 수집 메모)
 */
@Service
public class ExamCollectServiceImpl implements ExamCollectService {

    private static final Logger log = LoggerFactory.getLogger(ExamCollectServiceImpl.class);

    private final DataGoKrExamClient client;
    private final ExamRoundRepository examRoundRepository;
    private final SyncJobRepository syncJobRepository;
    private final String examCode;
    private final int configuredYear;

    public ExamCollectServiceImpl(DataGoKrExamClient client, ExamRoundRepository examRoundRepository,
                                  SyncJobRepository syncJobRepository,
                                  @Value("${passpace.certification-code}") String examCode,
                                  @Value("${passpace.collect.exam-year:0}") int configuredYear) {
        this.client = client;
        this.examRoundRepository = examRoundRepository;
        this.syncJobRepository = syncJobRepository;
        this.examCode = examCode;
        this.configuredYear = configuredYear;
    }

    @Override
    public CollectResult collectExamSchedule() {
        boolean useApi = client.hasKey();
        long sourceId = useApi ? CollectSources.EXAM_SCHEDULE_API : CollectSources.SAMPLE_SCHEDULE;
        String mode = useApi ? "API" : "SAMPLE(인증키 없음 - 실제 일정 아님)";
        long certId = examRoundRepository.findCertificationId(examCode)
                .orElseThrow(() -> new IllegalStateException("CERTIFICATIONS 에 종목코드 " + examCode + " 가 없습니다. db/03_seed.sql 을 먼저 실행하세요."));

        long jobId = syncJobRepository.start(sourceId, "EXAM_SCHEDULE");
        int success = 0, failed = 0, skipped = 0;
        try {
            // [3차] 올해 + 내년 일정을 함께 가져온다 (11~12월에는 올해 시험이 거의 끝나 내년 일정이 필요)
            //  내년 일정이 아직 공고 전이면 0건이거나 오류일 수 있으므로 내년 실패는 무시한다
            int year = configuredYear > 0 ? configuredYear : LocalDate.now().getYear();
            List<ExamScheduleItem> items = new ArrayList<>();
            String nextYearNote = "";
            if (useApi) {
                items.addAll(client.fetch(year, examCode));
                if (configuredYear <= 0) {
                    try {
                        List<ExamScheduleItem> next = client.fetch(year + 1, examCode);
                        items.addAll(next);
                        nextYearNote = next.isEmpty() ? " (" + (year + 1) + "년 일정은 아직 공고 전)" : " (" + (year + 1) + "년 " + next.size() + "건 포함)";
                    } catch (CollectException e) {
                        nextYearNote = " (" + (year + 1) + "년 일정 조회 실패: " + e.getFailType() + ")";
                    }
                }
            } else {
                items.addAll(client.readSample());
            }
            if (items.isEmpty()) {
                // 기획안 7.2.3: 파싱 결과 0건이면 이전 정상 데이터를 유지하고 실패로 기록
                syncJobRepository.finish(jobId, 0, 0, 0, "FAILED", "EMPTY_RESULT", "수집 결과 0건 - 기존 데이터 유지");
                return new CollectResult("EXAM_SCHEDULE", mode, 0, 0, 0, "FAILED", "수집 결과가 0건입니다. 기존 데이터를 유지합니다.");
            }

            for (ExamScheduleItem item : items) {
                try {
                    var stored = examRoundRepository.find(certId, item.examYear(), item.roundNo(), item.examType().name());
                    if (stored.isEmpty()) {
                        examRoundRepository.insert(certId, sourceId, examCode, item);
                        success++;
                    } else {
                        String changed = changedFields(stored.get(), item);
                        if (changed == null) {
                            examRoundRepository.touch(stored.get().examRoundId());
                            skipped++;          // 바뀐 것 없음
                        } else {
                            examRoundRepository.insertChangeLog(stored.get().examRoundId(), jobId, stored.get(), item, changed);
                            examRoundRepository.update(stored.get().examRoundId(), sourceId, item);
                            success++;
                        }
                    }
                } catch (Exception e) {
                    failed++;
                    log.warn("회차 저장 실패 {}년 {}회 {}: {}", item.examYear(), item.roundNo(), item.examType(), e.getMessage());
                }
            }
            String status = failed == 0 ? "SUCCESS" : "PARTIAL";
            syncJobRepository.finish(jobId, success, failed, skipped, status, null, null);
            return new CollectResult("EXAM_SCHEDULE", mode, success, failed, skipped, status,
                    "저장·변경 " + success + "건, 변경 없음 " + skipped + "건, 실패 " + failed + "건" + nextYearNote);
        } catch (CollectException e) {
            syncJobRepository.finish(jobId, success, failed, skipped, "FAILED", e.getFailType(), e.getMessage());
            return new CollectResult("EXAM_SCHEDULE", mode, success, failed, skipped, "FAILED", e.getMessage());
        }
    }

    /** 바뀐 항목 이름을 JSON 배열 문자열로. 바뀐 게 없으면 null */
    private String changedFields(StoredRound before, ExamScheduleItem after) {
        List<String> changed = new ArrayList<>();
        if (!Objects.equals(before.regStart(), after.regStart())) changed.add("\"reg_start_at\"");
        if (!Objects.equals(before.regEnd(), after.regEnd())) changed.add("\"reg_end_at\"");
        if (!Objects.equals(before.examStart(), after.examStart())) changed.add("\"exam_start_date\"");
        if (!Objects.equals(before.examEnd(), after.examEnd())) changed.add("\"exam_end_date\"");
        if (!Objects.equals(before.resultDate(), after.resultDate())) changed.add("\"result_date\"");
        return changed.isEmpty() ? null : "[" + String.join(",", changed) + "]";
    }
}
