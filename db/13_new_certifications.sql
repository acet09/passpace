-- =====================================================================
-- [11-26] 추가 자격증 1단계: 산업안전기사(SAFETY) · 컴퓨터활용능력 2급(CA2)
--   근거: 후기 측정(probe) 산업안전기사 882건, 컴활 2급 1,162건(2급만 다룬 글 822건) → 기준 500건 이상
--   코드는 CertificateDetector.SAFETY / COMPUTER2_CODE 와 같아야 한다.
--   실행 순서: 12_certification_info.sql 다음 (CERTIFICATION_INFO 를 함께 채움)
--   과목명은 공식 출제기준으로 최종 확인 필요 (기존 seed 와 같은 방식)
-- =====================================================================

-- 1) 자격증 (번호 5, 6 고정: 앱 플래너 key "db-5-WRITTEN" 등)
INSERT INTO CERTIFICATIONS (certification_id, cert_name, cert_type, issuing_org, source_exam_code, active_yn, pass_criteria)
SELECT 5, '산업안전기사', '국가기술자격(기사)', '한국산업인력공단', 'SAFETY', 'Y',
       '필기: 과목당 40점 이상·전 과목 평균 60점 이상 / 실기: 60점 이상 (큐넷에서 확인 필요)'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM CERTIFICATIONS WHERE certification_id = 5 OR source_exam_code = 'SAFETY');

INSERT INTO CERTIFICATIONS (certification_id, cert_name, cert_type, issuing_org, source_exam_code, active_yn, pass_criteria)
SELECT 6, '컴퓨터활용능력 2급', '국가기술자격', '대한상공회의소', 'CA2', 'Y', NULL
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM CERTIFICATIONS WHERE certification_id = 6 OR source_exam_code = 'CA2');

-- 2) 과목 (번호는 자동 증가, 자격증은 source_exam_code 로 찾음. 같은 과목이 있으면 넣지 않음)
INSERT INTO CERTIFICATION_SUBJECTS (certification_id, subject_name, exam_type, display_order, scope_version, source_id)
SELECT c.certification_id, v.subject_name, v.exam_type, v.display_order, v.scope_version, NULL
FROM CERTIFICATIONS c
JOIN (
  SELECT 'SAFETY' AS code, '산업재해 예방 및 안전보건교육' AS subject_name, 'WRITTEN' AS exam_type, 1 AS display_order, '확인 필요' AS scope_version
  UNION ALL SELECT 'SAFETY', '인간공학 및 위험성 평가·관리', 'WRITTEN', 2, '확인 필요'
  UNION ALL SELECT 'SAFETY', '기계·기구 및 설비 안전관리', 'WRITTEN', 3, '확인 필요'
  UNION ALL SELECT 'SAFETY', '전기설비 안전관리', 'WRITTEN', 4, '확인 필요'
  UNION ALL SELECT 'SAFETY', '화학설비 안전관리', 'WRITTEN', 5, '확인 필요'
  UNION ALL SELECT 'SAFETY', '건설공사 안전관리', 'WRITTEN', 6, '확인 필요'
  UNION ALL SELECT 'SAFETY', '산업안전관리 실무', 'PRACTICAL', 1, '확인 필요'
  UNION ALL SELECT 'CA2', '컴퓨터 일반', 'WRITTEN', 1, '2024~2026'
  UNION ALL SELECT 'CA2', '스프레드시트 일반', 'WRITTEN', 2, '2024~2026'
  UNION ALL SELECT 'CA2', '스프레드시트 실무', 'PRACTICAL', 1, '2024~2026'
) v ON v.code = c.source_exam_code
WHERE NOT EXISTS (SELECT 1 FROM CERTIFICATION_SUBJECTS s
                  WHERE s.certification_id = c.certification_id AND s.subject_name = v.subject_name AND s.exam_type = v.exam_type);

-- 3) 자격증 정보 메뉴 (db/12 의 표). 확실한 값만
INSERT INTO CERTIFICATION_INFO (certification_id, grade, category, summary, always_open_yn, written_exemption, validity,
                                related_certs, official_url, apply_url)
SELECT c.certification_id, v.grade, v.category, v.summary, v.always_open_yn, v.written_exemption, v.validity,
       v.related_certs, v.official_url, v.apply_url
FROM CERTIFICATIONS c
JOIN (
  SELECT 'SAFETY' AS code, '기사' AS grade, '안전' AS category,
         '사업장의 산업재해 예방 계획을 세우고 안전 관리 업무를 맡는 기사 등급 자격' AS summary, 'N' AS always_open_yn,
         '필기 합격 발표일부터 2년간 필기 면제' AS written_exemption, '없음 (갱신 불필요)' AS validity,
         '산업안전산업기사, 건설안전기사' AS related_certs, 'https://www.q-net.or.kr' AS official_url, 'https://www.q-net.or.kr' AS apply_url
  UNION ALL SELECT 'CA2', '2급', '사무·회계', '스프레드시트 활용 능력을 검정하는 사무 자격 (컴활 1급의 아래 단계)', 'Y',
         NULL, NULL, '컴퓨터활용능력 1급', 'https://license.korcham.net', 'https://license.korcham.net'
) v ON v.code = c.source_exam_code
ON DUPLICATE KEY UPDATE grade = VALUES(grade), category = VALUES(category), summary = VALUES(summary),
  always_open_yn = VALUES(always_open_yn), written_exemption = VALUES(written_exemption), validity = VALUES(validity),
  related_certs = VALUES(related_certs), official_url = VALUES(official_url), apply_url = VALUES(apply_url);

INSERT IGNORE INTO CERTIFICATION_EXAM_INFO (certification_id, exam_type)
SELECT c.certification_id, t.exam_type
FROM CERTIFICATIONS c
JOIN (SELECT 'WRITTEN' AS exam_type UNION ALL SELECT 'PRACTICAL') t
WHERE c.source_exam_code IN ('SAFETY', 'CA2');

-- 참고(확인 필요, 11-24 조사값): 산업안전기사 응시료 필기 19,400 / 실기 34,600 → 공식 확인 후 CERTIFICATION_EXAM_INFO 에 입력
