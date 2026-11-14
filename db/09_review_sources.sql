-- =====================================================================
-- [용성·11-14] 컴퓨터활용능력 1급 · ADsP 자격증·과목 기준 데이터 (데이터 행만 추가)
--
--  - DDL 없음: 테이블·칼럼·외래키·인덱스는 바꾸지 않는다 (passpace_merged 구조 그대로)
--  - DATA_SOURCES 행은 추가하지 않는다 → 새 출처(디시·네이버·dataq) 데이터는 source_id NULL, 사이트는 주소로 구분
--  - 여러 번 실행해도 안전하다: 같은 번호·같은 코드(·같은 과목)가 이미 있으면 넣지 않는다 (INSERT … SELECT … FROM DUAL WHERE NOT EXISTS)
--  - certification_id 3·4 와 source_exam_code 'CA1'·'ADSP' 는 팀 합의 전 임시값.
--    프로그램은 번호가 아니라 source_exam_code 로 자격증을 찾으므로, 번호가 달라져도 동작한다
--  - 이 파일을 실행하기 전에는 컴활·ADsP 후기·일정은 "자격증 미등록"으로 건너뛴다 (서버는 정상 동작)
--
-- 실행: DBeaver 에서 passpace_merged 연결 → 이 파일 전체 실행(Alt+X)
-- =====================================================================
USE passpace_merged;

-- 1) 자격증 2행 ------------------------------------------------------------
INSERT INTO CERTIFICATIONS (certification_id, cert_name, cert_type, issuing_org, source_exam_code, active_yn, pass_criteria)
SELECT 3, '컴퓨터활용능력 1급', '국가기술자격', '대한상공회의소', 'CA1', 'Y', NULL
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM CERTIFICATIONS WHERE certification_id = 3 OR source_exam_code = 'CA1');

INSERT INTO CERTIFICATIONS (certification_id, cert_name, cert_type, issuing_org, source_exam_code, active_yn, pass_criteria)
SELECT 4, 'ADsP', '국가공인 민간자격', '한국데이터산업진흥원', 'ADSP', 'Y', NULL
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM CERTIFICATIONS WHERE certification_id = 4 OR source_exam_code = 'ADSP');

-- 2) 과목 8행 (번호는 자동 증가, 자격증 번호는 source_exam_code 로 찾음) ---------
--    컴활 1급: 필기 3과목 / 실기 2과목 (scope_version '2024~2026')
INSERT INTO CERTIFICATION_SUBJECTS (certification_id, subject_name, exam_type, display_order, scope_version, source_id)
SELECT c.certification_id, v.subject_name, v.exam_type, v.display_order, '2024~2026', NULL
FROM CERTIFICATIONS c
JOIN (
    SELECT '컴퓨터 일반' AS subject_name, 'WRITTEN' AS exam_type, 1 AS display_order FROM DUAL
    UNION ALL SELECT '스프레드시트 일반', 'WRITTEN', 2 FROM DUAL
    UNION ALL SELECT '데이터베이스 일반', 'WRITTEN', 3 FROM DUAL
    UNION ALL SELECT '스프레드시트 실무', 'PRACTICAL', 1 FROM DUAL
    UNION ALL SELECT '데이터베이스 실무', 'PRACTICAL', 2 FROM DUAL
) v
WHERE c.source_exam_code = 'CA1'
  AND NOT EXISTS (SELECT 1 FROM CERTIFICATION_SUBJECTS s
                  WHERE s.certification_id = c.certification_id
                    AND s.subject_name = v.subject_name AND s.exam_type = v.exam_type);

--    ADsP: 필기 3과목 (실기 없음, scope_version '2026')
INSERT INTO CERTIFICATION_SUBJECTS (certification_id, subject_name, exam_type, display_order, scope_version, source_id)
SELECT c.certification_id, v.subject_name, v.exam_type, v.display_order, '2026', NULL
FROM CERTIFICATIONS c
JOIN (
    SELECT '데이터 이해' AS subject_name, 'WRITTEN' AS exam_type, 1 AS display_order FROM DUAL
    UNION ALL SELECT '데이터분석 기획', 'WRITTEN', 2 FROM DUAL
    UNION ALL SELECT '데이터분석', 'WRITTEN', 3 FROM DUAL
) v
WHERE c.source_exam_code = 'ADSP'
  AND NOT EXISTS (SELECT 1 FROM CERTIFICATION_SUBJECTS s
                  WHERE s.certification_id = c.certification_id
                    AND s.subject_name = v.subject_name AND s.exam_type = v.exam_type);

-- 확인
SELECT certification_id, cert_name, source_exam_code FROM CERTIFICATIONS ORDER BY certification_id;
SELECT s.certification_id, c.source_exam_code, s.exam_type, s.display_order, s.subject_name
FROM CERTIFICATION_SUBJECTS s JOIN CERTIFICATIONS c ON c.certification_id = s.certification_id
WHERE c.source_exam_code IN ('CA1', 'ADSP')
ORDER BY s.certification_id, s.exam_type DESC, s.display_order;
