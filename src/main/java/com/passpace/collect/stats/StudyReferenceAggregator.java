package com.passpace.collect.stats;

import com.passpace.common.code.ExamType;
import com.passpace.common.code.MajorType;
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
            for (ExamType exam : ExamType.values()) {
                for (String major : majors) {
                    lines.add(refreshOne(certId, exam.name(), major));
                }
            }
        }
        return lines;
    }

    AggregateLine refreshOne(long certId, String exam, String major) {
        // 합격 후기만, 실제 수집 출처만(더미·샘플 제외), 같은 작성자 1표본, 최근 3년
        // 총 공부시간이 적힌 글은 그 값을, 없으면 준비기간 × 하루시간으로 환산한다 (환산 건수는 근거 문장에 따로 표시)
        int[] converted = {0};
        List<Double> hours = jdbc.query("""
                SELECT total_hours, prep_days, daily_minutes
                FROM (
                    SELECT p.total_hours, p.prep_days, p.daily_minutes, p.major_type,
                           ROW_NUMBER() OVER (
                               PARTITION BY COALESCE(p.author_hash, CONCAT('row-', p.review_id))
                               ORDER BY p.posted_at DESC, p.review_id DESC) AS author_rank
                    FROM PASS_REVIEWS p
                    JOIN DATA_SOURCES d ON d.source_id = p.source_id
                    WHERE p.certification_id = ? AND p.exam_type = ?
                      AND p.review_status = 'VALID' AND p.pass_yn = 'Y'
                      AND d.source_type NOT IN ('DUMMY', 'SAMPLE')
                      AND (p.posted_at IS NULL OR p.posted_at >= DATE_SUB(CURDATE(), INTERVAL 3 YEAR))
                ) t
                WHERE author_rank = 1 AND (? IS NULL OR major_type = ?)
                """, (rs, n) -> {
                    Double total = rs.getObject("total_hours") == null ? null : rs.getDouble("total_hours");
                    Double h = ReferenceMath.reviewHours(total,
                            (Integer) rs.getObject("prep_days", Integer.class),
                            (Integer) rs.getObject("daily_minutes", Integer.class));
                    if (total == null && h != null) converted[0]++;
                    return h;
                },
                certId, exam, major, major)
                .stream().filter(h -> h != null).toList();

        String key = ReferenceMath.statKey(certId, exam, null, major);
        if (hours.size() < minSample) {
            jdbc.update("DELETE FROM STUDY_REFERENCE_STATS WHERE stat_key = ? AND stat_status = 'VERIFIED'", key + ":V");
            return new AggregateLine(certId, exam, major, hours.size(), null,
                    "표본 부족(" + hours.size() + "/" + minSample + ") → 잠정값 사용");
        }
        double mean = ReferenceMath.round2(hours.stream().mapToDouble(Double::doubleValue).average().orElse(0));
        double min = hours.stream().mapToDouble(Double::doubleValue).min().orElse(0);
        double max = hours.stream().mapToDouble(Double::doubleValue).max().orElse(0);
        String note = "합격 후기 " + hours.size() + "건(작성자당 1건, 최근 3년) 실측 평균 (범위 " + min + "~" + max + "시간"
                + (major == null ? ", 전공 전체" : ", " + MajorType.fromCode(major).getLabel())
                + (converted[0] > 0 ? ", 이 중 " + converted[0] + "건은 준비기간×하루시간 환산" : "") + ")";
        jdbc.update("""
                INSERT INTO STUDY_REFERENCE_STATS
                  (certification_id, exam_type, certification_subject_id, major_type, mean_hours, min_hours, max_hours,
                   sample_count, base_date, stat_status, source_id, source_note, stat_key, updated_at)
                VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, 'VERIFIED', NULL, ?, ?, NOW())
                ON DUPLICATE KEY UPDATE mean_hours = VALUES(mean_hours), min_hours = VALUES(min_hours),
                  max_hours = VALUES(max_hours), sample_count = VALUES(sample_count), base_date = VALUES(base_date),
                  source_note = VALUES(source_note), updated_at = NOW()
                """, certId, exam, major, mean, min, max, hours.size(), LocalDate.now(), note, key + ":V");
        return new AggregateLine(certId, exam, major, hours.size(), mean, "VERIFIED 저장");
    }
}
