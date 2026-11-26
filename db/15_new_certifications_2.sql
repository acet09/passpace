-- =====================================================================
-- [11-26] 추가 자격증 2단계: 빅데이터분석기사(BIGDATA, 7) · 전산회계 1급(ACC1, 8) · 전산회계 2급(ACC2, 9)
--   근거: 섞인 글 분리 조건 적용 측정 빅분기 1,096 / 전산회계 2급 813 / 1급 1,947 (probe-20261126-0946)
--   코드는 CertificateDetector.BIGDATA / ACCOUNTING1 / ACCOUNTING2 와 같아야 한다. db/12, 13, 14 다음에 실행
--   정보 값은 2026-11-26 웹 조사(수험정보 사이트의 공식 안내 인용). 확인 못 한 칸은 NULL
-- =====================================================================

-- 1) 자격증
INSERT INTO CERTIFICATIONS (certification_id, cert_name, cert_type, issuing_org, source_exam_code, active_yn, pass_criteria)
SELECT 7, '빅데이터분석기사', '국가기술자격(기사)', '한국데이터산업진흥원', 'BIGDATA', 'Y',
       '필기: 과목당 40점 이상·전 과목 평균 60점 이상 / 실기: 60점 이상 (데이터자격검정에서 확인 필요)'
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM CERTIFICATIONS WHERE certification_id = 7 OR source_exam_code = 'BIGDATA');
INSERT INTO CERTIFICATIONS (certification_id, cert_name, cert_type, issuing_org, source_exam_code, active_yn, pass_criteria)
SELECT 8, '전산회계 1급', '국가공인 민간자격', '한국세무사회', 'ACC1', 'Y', '100점 만점에 70점 이상 (과락 없음)'
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM CERTIFICATIONS WHERE certification_id = 8 OR source_exam_code = 'ACC1');
INSERT INTO CERTIFICATIONS (certification_id, cert_name, cert_type, issuing_org, source_exam_code, active_yn, pass_criteria)
SELECT 9, '전산회계 2급', '국가공인 민간자격', '한국세무사회', 'ACC2', 'Y', '100점 만점에 70점 이상 (과락 없음)'
FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM CERTIFICATIONS WHERE certification_id = 9 OR source_exam_code = 'ACC2');

-- 2) 과목 (전산회계는 이론+실무를 한 번에 보는 시험 → WRITTEN 하나로 저장, SQLD·ADsP 와 같은 방식)
INSERT INTO CERTIFICATION_SUBJECTS (certification_id, subject_name, exam_type, display_order, scope_version, source_id)
SELECT c.certification_id, v.subject_name, v.exam_type, v.display_order, v.scope_version, NULL
FROM CERTIFICATIONS c
JOIN (
  SELECT 'BIGDATA' AS code, '빅데이터 분석 기획' AS subject_name, 'WRITTEN' AS exam_type, 1 AS display_order, '확인 필요' AS scope_version
  UNION ALL SELECT 'BIGDATA', '빅데이터 탐색', 'WRITTEN', 2, '확인 필요'
  UNION ALL SELECT 'BIGDATA', '빅데이터 모델링', 'WRITTEN', 3, '확인 필요'
  UNION ALL SELECT 'BIGDATA', '빅데이터 결과 해석', 'WRITTEN', 4, '확인 필요'
  UNION ALL SELECT 'BIGDATA', '빅데이터 분석 실무', 'PRACTICAL', 1, '확인 필요'
  UNION ALL SELECT 'ACC1', '이론 (회계원리·원가회계·세무회계)', 'WRITTEN', 1, '2026'
  UNION ALL SELECT 'ACC1', '실무 (KcLep 프로그램)', 'WRITTEN', 2, '2026'
  UNION ALL SELECT 'ACC2', '이론 (회계원리)', 'WRITTEN', 1, '2026'
  UNION ALL SELECT 'ACC2', '실무 (KcLep 프로그램)', 'WRITTEN', 2, '2026'
) v ON v.code = c.source_exam_code
WHERE NOT EXISTS (SELECT 1 FROM CERTIFICATION_SUBJECTS s
                  WHERE s.certification_id = c.certification_id AND s.subject_name = v.subject_name AND s.exam_type = v.exam_type);

-- 3) 자격증 정보 메뉴
INSERT INTO CERTIFICATION_INFO (certification_id, grade, category, summary, eligibility, eligibility_check_url, always_open_yn,
                                written_exemption, validity, related_certs, official_url, apply_url, info_verified_at)
SELECT c.certification_id, v.grade, v.category, v.summary, v.eligibility, v.check_url, 'N',
       v.exemption, v.validity, v.related, v.url, v.url, '2026-11-26'
FROM CERTIFICATIONS c
JOIN (
  SELECT 'BIGDATA' AS code, '기사' AS grade, '데이터' AS category,
         '빅데이터 분석 기획·수집·처리·분석·시각화를 다루는 데이터 분야 국가기술자격' AS summary,
         '학력·경력 요건 있음 (기사 등급 기준)\n필기 합격 후 응시자격 서류를 기간 안에 내야 함' AS eligibility,
         'https://www.dataq.or.kr' AS check_url, '필기 합격자 발표일부터 2년간 필기 면제' AS exemption,
         '없음 (갱신 불필요)' AS validity, 'ADsP, SQLD, ADP' AS related, 'https://www.dataq.or.kr' AS url
  UNION ALL SELECT 'ACC1', '1급', '사무·회계', '재무회계·원가회계·부가가치세 기초와 회계 프로그램 실무를 검정하는 회계 자격',
         '제한 없음', NULL, NULL, NULL, '전산회계 2급, 전산세무 2급', 'https://license.kacpta.or.kr'
  UNION ALL SELECT 'ACC2', '2급', '사무·회계', '회계원리와 회계 프로그램(KcLep) 기초 실무를 검정하는 회계 입문 자격',
         '제한 없음', NULL, NULL, NULL, '전산회계 1급', 'https://license.kacpta.or.kr'
) v ON v.code = c.source_exam_code
ON DUPLICATE KEY UPDATE grade = VALUES(grade), category = VALUES(category), summary = VALUES(summary),
  eligibility = VALUES(eligibility), eligibility_check_url = VALUES(eligibility_check_url),
  written_exemption = VALUES(written_exemption), validity = VALUES(validity), related_certs = VALUES(related_certs),
  official_url = VALUES(official_url), apply_url = VALUES(apply_url), info_verified_at = VALUES(info_verified_at);

UPDATE CERTIFICATION_INFO i JOIN CERTIFICATIONS c ON c.certification_id = i.certification_id
   SET i.result_notice = '한국세무사회 홈페이지와 ARS(060-700-1921)'
 WHERE c.source_exam_code IN ('ACC1', 'ACC2');

-- 4) 시험 구분별 정보 (출처: winspec·wowpass·yugacrew 전산회계 2026 정리 — 한국세무사회 안내 인용,
--    linkareer 빅데이터분석기사 2026 정리 — 데이터자격검정 출제기준 인용)
INSERT IGNORE INTO CERTIFICATION_EXAM_INFO (certification_id, exam_type)
SELECT c.certification_id, t.exam_type FROM CERTIFICATIONS c
JOIN (SELECT 'WRITTEN' AS exam_type UNION ALL SELECT 'PRACTICAL') t
WHERE c.source_exam_code = 'BIGDATA' OR (c.source_exam_code IN ('ACC1', 'ACC2') AND t.exam_type = 'WRITTEN');

UPDATE CERTIFICATION_EXAM_INFO e JOIN CERTIFICATIONS c ON c.certification_id = e.certification_id
   SET e.exam_method = '객관식 필기 (4과목)', e.pass_criteria = '과목당 40점 이상 + 전 과목 평균 60점 이상'
 WHERE c.source_exam_code = 'BIGDATA' AND e.exam_type = 'WRITTEN';
UPDATE CERTIFICATION_EXAM_INFO e JOIN CERTIFICATIONS c ON c.certification_id = e.certification_id
   SET e.duration_minutes = 180, e.exam_method = '작업형 (코드로 데이터 수집·전처리·모형 구축·평가)',
       e.pass_criteria = '100점 만점에 60점 이상'
 WHERE c.source_exam_code = 'BIGDATA' AND e.exam_type = 'PRACTICAL';
UPDATE CERTIFICATION_EXAM_INFO e JOIN CERTIFICATIONS c ON c.certification_id = e.certification_id
   SET e.exam_fee = 30000, e.duration_minutes = 60,
       e.exam_method = '이론 30% (객관식 4지 선다) + 실무 70% (KcLep 프로그램)', e.pass_criteria = '100점 만점에 70점 이상 (과락 없음)'
 WHERE c.source_exam_code IN ('ACC1', 'ACC2') AND e.exam_type = 'WRITTEN';

-- 5) 시험 일정 (남은 2026 회차, 고정값. 빅분기 일정은 관리자 "자격증 정보 수집"이 공공 API에서 다시 가져옴)
--    전산회계 제129회: 접수 11.5~11.11, 시험 12.5(토), 발표 12.24 (yugacrew, 한국세무사회 원문 인용)
--    빅데이터분석기사 제13회 실기: 접수 10.26~10.30, 시험 11.28(토), 발표 12.18 (wowpass 접수 안내)
INSERT INTO EXAM_ROUNDS (certification_id, source_id, source_exam_code, exam_year, round_no, exam_type,
                         reg_start_at, reg_end_at, exam_date, exam_start_date, exam_end_date, result_date, last_synced_at)
SELECT c.certification_id, NULL, c.source_exam_code, v.y, v.r, v.t, v.rs, v.re, v.ex, v.ex, v.ex, v.rd, NOW()
FROM CERTIFICATIONS c
JOIN (
  SELECT 'ACC1' AS code, 2026 AS y, 129 AS r, 'WRITTEN' AS t, '2026-11-05 10:00:00' AS rs, '2026-11-11 18:00:00' AS re,
         DATE '2026-12-05' AS ex, DATE '2026-12-24' AS rd
  UNION ALL SELECT 'ACC2', 2026, 129, 'WRITTEN', '2026-11-05 10:00:00', '2026-11-11 18:00:00', DATE '2026-12-05', DATE '2026-12-24'
  UNION ALL SELECT 'BIGDATA', 2026, 13, 'PRACTICAL', '2026-10-26 10:00:00', '2026-10-30 18:00:00', DATE '2026-11-28', DATE '2026-12-18'
) v ON v.code = c.source_exam_code
WHERE NOT EXISTS (SELECT 1 FROM EXAM_ROUNDS e WHERE e.certification_id = c.certification_id
                  AND e.exam_year = v.y AND e.round_no = v.r AND e.exam_type = v.t);
