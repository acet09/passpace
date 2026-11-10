package com.passpace.collect.stats;

import com.passpace.common.code.ExamType;
import com.passpace.common.code.MajorType;
import com.passpace.common.reference.StudyReference;
import com.passpace.common.reference.StudyReference.SubjectHours;
import com.passpace.common.reference.StudyReferenceQuery;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * [용성 → 동건 제공] 공통 계약 StudyReferenceQuery 구현. STUDY_REFERENCE_STATS 를 읽는다.
 *
 * 1) 해당 전공 VERIFIED → 2) 전공 전체 VERIFIED → 3) PROVISIONAL 순서로 자격증 전체 시간을 고른다.
 * 과목별 시간은 VERIFIED 총시간 × 잠정 과목 비율 (ReferenceMath.splitByRatio).
 * 행 자체는 03_seed.sql(잠정값)과 StudyReferenceAggregator(후기 집계)가 만든다.
 */
@Component
public class JdbcStudyReferenceQuery implements StudyReferenceQuery {

    private final JdbcTemplate jdbc;

    public JdbcStudyReferenceQuery(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public Optional<StudyReference> find(long certificationId, ExamType examType, MajorType major) {
        String exam = examType.name();
        Map<String, Object> verified = null;
        MajorType appliedMajor = null;
        if (major != null) {
            verified = totalRow(certificationId, exam, major.name(), "VERIFIED");
            if (verified != null) appliedMajor = major;
        }
        if (verified == null) {
            verified = totalRow(certificationId, exam, null, "VERIFIED");
        }
        Map<String, Object> provisional = totalRow(certificationId, exam, null, "PROVISIONAL");
        Map<String, Object> chosen = verified != null ? verified : provisional;

        // 과목 목록(순서) + 과목별 잠정 시간
        List<Map<String, Object>> subjectRows = jdbc.queryForList("""
                SELECT s.certification_subject_id AS subject_id, s.subject_name,
                       r.mean_hours AS provisional_hours, r.source_note
                FROM CERTIFICATION_SUBJECTS s
                LEFT JOIN STUDY_REFERENCE_STATS r
                       ON r.certification_subject_id = s.certification_subject_id
                      AND r.major_type IS NULL AND r.stat_status = 'PROVISIONAL'
                WHERE s.certification_id = ? AND s.exam_type = ?
                ORDER BY s.display_order, s.certification_subject_id
                """, certificationId, exam);
        if (chosen == null && subjectRows.stream().allMatch(r -> r.get("provisional_hours") == null)) {
            return Optional.empty();
        }

        List<Double> provisionalHours = new ArrayList<>();
        for (Map<String, Object> r : subjectRows) {
            provisionalHours.add(toDouble(r.get("provisional_hours")));
        }
        double total = chosen != null ? toDouble(chosen.get("mean_hours"))
                : provisionalHours.stream().filter(h -> h != null).mapToDouble(Double::doubleValue).sum();
        int sample = chosen != null && chosen.get("sample_count") != null ? ((Number) chosen.get("sample_count")).intValue() : 0;
        boolean isVerified = verified != null;

        List<SubjectHours> subjects = new ArrayList<>();
        if (isVerified) {
            List<Double> split = ReferenceMath.splitByRatio(total, provisionalHours);
            for (int i = 0; i < subjectRows.size(); i++) {
                Map<String, Object> r = subjectRows.get(i);
                subjects.add(new SubjectHours(((Number) r.get("subject_id")).longValue(), (String) r.get("subject_name"),
                        split.get(i), "총 학습시간 실측 " + sample + "건 평균 × 과목 비율(잠정)"));
            }
        } else {
            for (int i = 0; i < subjectRows.size(); i++) {
                Map<String, Object> r = subjectRows.get(i);
                Double h = provisionalHours.get(i);
                subjects.add(new SubjectHours(((Number) r.get("subject_id")).longValue(), (String) r.get("subject_name"),
                        h == null ? 0 : h, r.get("source_note") == null ? "잠정값" : "잠정값 · " + r.get("source_note")));
            }
        }
        String note = chosen == null ? "과목별 잠정값만 있음"
                : (String) chosen.get("source_note");
        return Optional.of(new StudyReference(certificationId, examType, appliedMajor, ReferenceMath.round2(total), sample,
                isVerified ? toDouble(chosen.get("min_hours")) : null,
                isVerified ? toDouble(chosen.get("max_hours")) : null,
                isVerified, note, List.copyOf(subjects)));
    }

    /** 자격증 전체(과목 NULL) 행 하나. major 가 null 이면 전공 구분 없는 행 */
    private Map<String, Object> totalRow(long certId, String exam, String major, String status) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT mean_hours, min_hours, max_hours, sample_count, source_note
                FROM STUDY_REFERENCE_STATS
                WHERE certification_id = ? AND exam_type = ? AND certification_subject_id IS NULL
                  AND stat_status = ? AND (major_type <=> ?)
                ORDER BY updated_at DESC LIMIT 1
                """, certId, exam, status, major);
        return rows.isEmpty() ? null : rows.get(0);
    }

    private static Double toDouble(Object v) {
        return v == null ? null : ((Number) v).doubleValue();
    }
}
