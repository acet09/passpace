-- =====================================================================
-- [용성·11-20] ADsP·컴활 1급 과목 잠정값(PROVISIONAL) 채우기 — 공식 문항·배점 비율
--
-- 왜 필요한가
--   - 용성이 동건에게 주는 과목별 학습시간(StudyReference.subjects)은
--     "총학습량 실측 중앙값 × 과목 잠정값 비율"로 계산한다 (JdbcStudyReferenceQuery, 코드 수정 없음)
--   - 정보처리기사·SQLD 는 db/03 에 과목 잠정값(합격자 1인 일지)이 있지만
--     ADsP·컴활 1급은 과목 잠정값이 없어 과목 시간이 똑같이 나뉘었다
--   - 후기 991건 중 과목별 시간이 적힌 글이 몇 건뿐이라 후기 실측 과목 평균은 낼 수 없다 (팀 합의)
--     → 공식 문항·배점 비율을 잠정값으로 넣는다. 동건 플래너(StudyHoursEvidence)와 같은 비율이다
--
-- 넣는 값 (mean_hours 는 비율로만 쓰인다. 숫자 = 동건 코드의 총 시간 × 공식 비율, 참고용)
--   ADsP 필기      : 데이터 이해 10 · 데이터분석 기획 10 · 데이터분석 30 문항 → 8.74 / 8.74 / 26.22
--   컴활 1급 필기  : 컴퓨터 일반 · 스프레드시트 일반 · 데이터베이스 일반 각 20문항 → 12.83 × 3
--   컴활 1급 실기  : 스프레드시트 실무 · 데이터베이스 실무 각 100점 → 30.00 × 2
--
-- 규칙
--   - 과목 번호는 이름으로 찾는다 (컴활·ADsP 과목 번호는 PC마다 다를 수 있음, db/09 참고)
--   - 여러 번 실행해도 안전하다 (stat_key 중복이면 값만 갱신)
--   - 동건 코드·다른 테이블은 바꾸지 않는다
--
-- 실행: DBeaver 에서 passpace_merged 연결 → 이 파일 전체 실행(Alt+X)
-- 되돌리기: 맨 아래 [되돌리기] 주석의 DELETE 문 실행
-- =====================================================================
USE passpace_merged;

-- [실행 전 확인] provisional_hours 가 비어 있으면 그 자격증 과목은 똑같이 나뉘는 중
SELECT c.certification_id, c.cert_name, s.exam_type, s.subject_name, r.mean_hours AS provisional_hours
FROM CERTIFICATION_SUBJECTS s
JOIN CERTIFICATIONS c ON c.certification_id = s.certification_id
LEFT JOIN STUDY_REFERENCE_STATS r
       ON r.certification_subject_id = s.certification_subject_id
      AND r.major_type IS NULL AND r.stat_status = 'PROVISIONAL'
ORDER BY c.certification_id, s.exam_type, s.display_order;

INSERT INTO STUDY_REFERENCE_STATS
  (certification_id, exam_type, certification_subject_id, major_type, mean_hours, min_hours, max_hours,
   sample_count, base_date, stat_status, source_id, source_note, stat_key, updated_at)
SELECT s.certification_id, s.exam_type, s.certification_subject_id, NULL, v.hours, NULL, NULL,
       0, '2026-11-20', 'PROVISIONAL', NULL, v.note,
       CONCAT(s.certification_id, ':', s.exam_type, ':', s.certification_subject_id, ':ALL'), NOW()
FROM CERTIFICATION_SUBJECTS s
JOIN (
    SELECT 4 AS cert_id, 'WRITTEN' AS exam_type, '데이터 이해' AS subject_name, 8.74 AS hours,
           '공식 문항 수 비율 10/50 (합격자 1인 실제 일정 1일:1일:3일과 일치). 과목별 실측 아님' AS note FROM DUAL
    UNION ALL SELECT 4, 'WRITTEN', '데이터분석 기획', 8.74, '공식 문항 수 비율 10/50. 과목별 실측 아님' FROM DUAL
    UNION ALL SELECT 4, 'WRITTEN', '데이터분석', 26.22, '공식 문항 수 비율 30/50. 과목별 실측 아님' FROM DUAL
    UNION ALL SELECT 3, 'WRITTEN', '컴퓨터 일반', 12.83, '공식 문항 수 비율 20/60. 과목별 실측 아님' FROM DUAL
    UNION ALL SELECT 3, 'WRITTEN', '스프레드시트 일반', 12.83, '공식 문항 수 비율 20/60. 과목별 실측 아님' FROM DUAL
    UNION ALL SELECT 3, 'WRITTEN', '데이터베이스 일반', 12.83, '공식 문항 수 비율 20/60. 과목별 실측 아님' FROM DUAL
    UNION ALL SELECT 3, 'PRACTICAL', '스프레드시트 실무', 30.00, '공식 배점 비율 100/200. 과목별 실측 아님' FROM DUAL
    UNION ALL SELECT 3, 'PRACTICAL', '데이터베이스 실무', 30.00, '공식 배점 비율 100/200. 과목별 실측 아님' FROM DUAL
) v ON v.cert_id = s.certification_id AND v.exam_type = s.exam_type AND v.subject_name = s.subject_name
ON DUPLICATE KEY UPDATE mean_hours = VALUES(mean_hours), source_note = VALUES(source_note),
                        base_date = VALUES(base_date), updated_at = NOW();

-- [실행 후 확인] ADsP·컴활 provisional_hours 가 모두 채워졌는지 (위 확인 쿼리 다시 실행)
SELECT c.cert_name, s.exam_type, s.subject_name, r.mean_hours AS provisional_hours, r.source_note
FROM STUDY_REFERENCE_STATS r
JOIN CERTIFICATION_SUBJECTS s ON s.certification_subject_id = r.certification_subject_id
JOIN CERTIFICATIONS c ON c.certification_id = r.certification_id
WHERE r.stat_status = 'PROVISIONAL' AND r.certification_id IN (3, 4)
ORDER BY c.certification_id, s.exam_type, s.display_order;

-- [되돌리기] 이 파일로 넣은 줄만 지운다
-- DELETE FROM STUDY_REFERENCE_STATS
-- WHERE stat_status = 'PROVISIONAL' AND certification_id IN (3, 4)
--   AND certification_subject_id IS NOT NULL AND base_date = '2026-11-20';
