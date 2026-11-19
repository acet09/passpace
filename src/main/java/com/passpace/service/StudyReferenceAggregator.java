package com.passpace.service;

import com.passpace.constant.ExamType;
import com.passpace.constant.MajorType;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * [용성] 합격 후기(PASS_REVIEWS) → 참고 학습시간(STUDY_REFERENCE_STATS) 집계.
 * 기획안 7.1.4: "유효 표본의 평균·범위·표본 수를 함께 제공 / 10건 미만이면 통계 미사용"
 *
 * - 대상: 실제 수집 후기만 (DATA_SOURCES.source_type 이 DUMMY·SAMPLE 인 것은 제외), VALID, 합격(pass_yn='Y')
 * - 후기 한 건의 시간: total_hours, 없으면 준비일수 × 하루 분 / 60
 * - [11-16] 대표값은 평균이 아니라 중앙값 (mean_hours 칸에 저장, 근거 문구에 "중앙값" 표시)
 * - (자격증, 시험구분, 전공별 + 전공 전체) 조합마다 표본이 최소 표본 이상이면 VERIFIED 행을 저장·갱신,
 *   부족하면 기존 VERIFIED 행을 지운다 → 조회 쪽은 자동으로 잠정값(PROVISIONAL)을 사용
 * - 잠정값 행은 건드리지 않는다 (과목 비율의 근거로 계속 쓰임)
 *
 * 실행: 후기 수집이 끝날 때 자동, 또는 POST /admin/collect/reference-stats
 */
@Service
public class StudyReferenceAggregator {

    /** 집계 결과 한 줄 (관리자 화면 표시용) */
    public record AggregateLine(long certificationId, String examType, String majorType,
                                int sampleCount, Double meanHours, String result) {
    }

    private final JdbcTemplate jdbc;
    private final int minSample;

    public StudyReferenceAggregator(JdbcTemplate jdbc, @Value("${passpace.stats.min-sample:10}") int minSample) {
        this.jdbc = jdbc;
        this.minSample = minSample;
    }

    @Transactional
    public List<AggregateLine> refreshAll() {
        List<AggregateLine> lines = new ArrayList<>();
        List<Long> certIds = jdbc.queryForList("SELECT certification_id FROM CERTIFICATIONS WHERE active_yn = 'Y'", Long.class);
        List<String> majors = new ArrayList<>(Arrays.stream(MajorType.values()).map(Enum::name).toList());
        majors.add(null);   // 전공 전체
        for (long certId : certIds) {
            // [11-20] 그 자격증에 있는 시험만 집계한다 (SQLD·ADsP 는 필기만 → 실기 줄을 만들지 않음)
            for (ExamType exam : examTypesOf(certId)) {
                // [11-19] 추정값을 섞을지는 전공 전체의 직접 값 수로 한 번만 정한다 (ReferenceMath.pickHours)
                Double fallbackDaily = fallbackDailyMinutes(certId, exam.name());
                int allMajorDirect = loadSamples(certId, exam.name(), null, fallbackDaily).direct().size();
                for (String major : majors) {
                    lines.add(refreshOne(certId, exam.name(), major, allMajorDirect, fallbackDaily));
                }
            }
        }
        return lines;
    }

    /**
     * [11-20] 자격증의 시험 구분: CERTIFICATION_SUBJECTS 에 과목이 있는 시험만 (SQLD·ADsP = 필기만).
     * 과목이 하나도 등록되지 않은 자격증은 예전처럼 모든 시험 구분을 본다.
     */
    List<ExamType> examTypesOf(long certId) {
        List<String> names = jdbc.queryForList(
                "SELECT DISTINCT exam_type FROM CERTIFICATION_SUBJECTS WHERE certification_id = ?", String.class, certId);
        List<ExamType> out = Arrays.stream(ExamType.values()).filter(e -> names.contains(e.name())).toList();
        return out.isEmpty() ? List.of(ExamType.values()) : out;
    }

    /** 한 그룹의 후기 시간: 직접 계산된 값(direct), 하루시간 중앙값으로 추정한 값(guessed), 환산 건수(converted) */
    record Samples(List<Double> direct, List<Double> guessed, int converted) {
    }

    AggregateLine refreshOne(long certId, String exam, String major, int allMajorDirect, Double fallbackDaily) {
        Samples s = loadSamples(certId, exam, major, fallbackDaily);
        List<Double> hours = ReferenceMath.pickHours(s.direct(), s.guessed(), allMajorDirect, minSample);
        int[] converted = {s.converted()};
        int[] estimated = {hours.size() - s.direct().size()};
        return save(certId, exam, major, hours, converted, estimated, fallbackDaily);
    }

    Samples loadSamples(long certId, String exam, String major, Double fallbackDaily) {
        // 합격 후기만, 실제 수집 출처만(더미·샘플 제외), 같은 작성자 1표본, 최근 3년
        // [11-14] source_id 가 NULL 인 새 출처 후기도 빠지지 않게 LEFT JOIN
        // 총 공부시간이 적힌 글은 그 값을, 없으면 준비기간 × 하루시간으로 환산한다 (환산 건수는 근거 문장에 따로 표시)
        // [11-16] 하루시간도 없으면("3일컷") 같은 자격증·시험 후기들의 하루시간 중앙값으로 추정한다.
        //         단, 직접 계산되는 후기가 최소 표본 이상이면 추정값은 쓰지 않는다 (추정은 쉬는 날까지 곱해 크게 나오기 쉬움)
        // [11-19] 이 판단은 전공 전체 기준으로 refreshAll 에서 한 번만 한다 (ReferenceMath.pickHours)
        int[] converted = {0};
        List<Double> direct = new ArrayList<>();
        List<Double> guessed = new ArrayList<>();
        jdbc.query("""
                SELECT total_hours, prep_days, daily_minutes
                FROM (
                    SELECT p.total_hours, p.prep_days, p.daily_minutes, p.major_type,
                           ROW_NUMBER() OVER (
                               PARTITION BY COALESCE(p.author_hash, CONCAT('row-', p.review_id))
                               ORDER BY p.posted_at DESC, p.review_id DESC) AS author_rank
                    FROM PASS_REVIEWS p
                    LEFT JOIN DATA_SOURCES d ON d.source_id = p.source_id
                    WHERE p.certification_id = ? AND p.exam_type = ?
                      AND p.review_status = 'VALID' AND p.pass_yn = 'Y'
                      AND (d.source_type IS NULL OR d.source_type NOT IN ('DUMMY', 'SAMPLE'))
                      AND (p.posted_at IS NULL OR p.posted_at >= DATE_SUB(CURDATE(), INTERVAL 3 YEAR))
                ) t
                WHERE author_rank = 1 AND (? IS NULL OR major_type = ?)
                """, (rs, n) -> {
                    Double total = rs.getObject("total_hours") == null ? null : rs.getDouble("total_hours");
                    Integer prep = (Integer) rs.getObject("prep_days", Integer.class);
                    Integer daily = (Integer) rs.getObject("daily_minutes", Integer.class);
                    Double h = ReferenceMath.reviewHours(total, prep, daily);
                    if (h != null) {
                        if (total == null) converted[0]++;
                        direct.add(h);
                        return null;
                    }
                    Double g = ReferenceMath.reviewHoursWithFallback(total, prep, daily, fallbackDaily);
                    if (g != null) guessed.add(g);
                    return null;
                },
                certId, exam, major, major);
        return new Samples(direct, guessed, converted[0]);
    }

    private AggregateLine save(long certId, String exam, String major, List<Double> hours,
                               int[] converted, int[] estimated, Double fallbackDaily) {
        String key = ReferenceMath.statKey(certId, exam, null, major);
        if (hours.size() < minSample) {
            jdbc.update("DELETE FROM STUDY_REFERENCE_STATS WHERE stat_key = ? AND stat_status = 'VERIFIED'", key + ":V");
            return new AggregateLine(certId, exam, major, hours.size(), null,
                    "표본 부족(" + hours.size() + "/" + minSample + ") → 잠정값 사용");
        }
        // [11-16] 평균 → 중앙값 (튀는 값 영향 감소). 칸 이름은 mean_hours 그대로 두고 값만 중앙값을 넣는다
        double mean = ReferenceMath.median(hours);
        double min = hours.stream().mapToDouble(Double::doubleValue).min().orElse(0);
        double max = hours.stream().mapToDouble(Double::doubleValue).max().orElse(0);
        String note = "합격 후기 " + hours.size() + "건(작성자당 1건, 최근 3년) 실측 중앙값 (범위 " + min + "~" + max + "시간"
                + (major == null ? ", 전공 전체" : ", " + MajorType.fromCode(major).getLabel())
                + (converted[0] > 0 ? ", 이 중 " + converted[0] + "건은 준비기간×하루시간 환산" : "")
                + (estimated[0] > 0 ? ", " + estimated[0] + "건은 준비기간×같은 시험 하루시간 중앙값("
                        + Math.round(fallbackDaily) + "분) 추정" : "") + ")";
        jdbc.update("""
                INSERT INTO STUDY_REFERENCE_STATS
                  (certification_id, exam_type, certification_subject_id, major_type, mean_hours, min_hours, max_hours,
                   sample_count, base_date, stat_status, source_id, source_note, stat_key, updated_at)
                VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, 'VERIFIED', NULL, ?, ?, NOW())
                ON DUPLICATE KEY UPDATE mean_hours = VALUES(mean_hours), min_hours = VALUES(min_hours),
                  max_hours = VALUES(max_hours), sample_count = VALUES(sample_count), base_date = VALUES(base_date),
                  source_note = VALUES(source_note), updated_at = NOW()
                """, certId, exam, major, mean, min, max, hours.size(), LocalDate.now(), note, key + ":V");
        return new AggregateLine(certId, exam, major, hours.size(), mean,
                "VERIFIED 저장" + (estimated[0] > 0 ? " (하루시간 추정 " + estimated[0] + "건 포함)" : ""));
    }

    /**
     * [11-16] 같은 자격증·시험의 합격 후기(VALID, 실제 출처, 최근 3년)에 적힌 하루 공부시간(분)의 중앙값.
     * 전공 구분 없이 계산한다 (전공별로 나누면 표본이 너무 적다). 하루시간이 적힌 후기가 없으면 null.
     */
    Double fallbackDailyMinutes(long certId, String exam) {
        List<Double> daily = jdbc.query("""
                SELECT p.daily_minutes
                FROM PASS_REVIEWS p
                LEFT JOIN DATA_SOURCES d ON d.source_id = p.source_id
                WHERE p.certification_id = ? AND p.exam_type = ?
                  AND p.review_status = 'VALID' AND p.pass_yn = 'Y'
                  AND p.daily_minutes IS NOT NULL AND p.daily_minutes > 0
                  AND (d.source_type IS NULL OR d.source_type NOT IN ('DUMMY', 'SAMPLE'))
                  AND (p.posted_at IS NULL OR p.posted_at >= DATE_SUB(CURDATE(), INTERVAL 3 YEAR))
                """, (rs, n) -> rs.getDouble("daily_minutes"), certId, exam);
        return daily == null || daily.isEmpty() ? null : ReferenceMath.median(daily);
    }
}
