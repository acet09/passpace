-- =====================================================================
-- [11-26] 자격증 정보 메뉴 값 채우기 (db/12, db/13 다음에 실행)
--   2026-11-26 웹 조사값. 대부분 수험정보 사이트 재인용이라 공식 사이트(큐넷·데이터자격검정·대한상의)로 최종 확인 권장.
--   확인 못 한 칸(SQLD 문항 수·시간 등)은 그대로 NULL → 앱에 "공식 사이트에서 확인"
--   여러 번 실행해도 같은 결과 (UPDATE 만 사용)
-- =====================================================================

-- ---------- 시험 구분별 정보 ----------
-- 정보처리기사 (출처: inflearn 2026 정보처리기사 가이드, linkareer 2026 응시료 정리)
UPDATE CERTIFICATION_EXAM_INFO e JOIN CERTIFICATIONS c ON c.certification_id = e.certification_id
   SET e.exam_fee = 19400, e.question_count = 100, e.duration_minutes = 150,
       e.exam_method = 'CBT · 객관식 4지 택일 (5과목)', e.pass_criteria = '과목당 40점 이상 + 전 과목 평균 60점 이상'
 WHERE c.source_exam_code = '1320' AND e.exam_type = 'WRITTEN';
UPDATE CERTIFICATION_EXAM_INFO e JOIN CERTIFICATIONS c ON c.certification_id = e.certification_id
   SET e.exam_fee = 22600, e.question_count = NULL, e.duration_minutes = 150,
       e.exam_method = '필답형 (정보처리 실무)', e.pass_criteria = '100점 만점에 60점 이상'
 WHERE c.source_exam_code = '1320' AND e.exam_type = 'PRACTICAL';

-- SQLD (출처: glasswallet SQLD 비용 가이드 — 응시료 50,000원. 문항 수·시간은 확인 필요라 비움)
UPDATE CERTIFICATION_EXAM_INFO e JOIN CERTIFICATIONS c ON c.certification_id = e.certification_id
   SET e.exam_fee = 50000, e.exam_method = '객관식 필기 (실기 없음)',
       e.pass_criteria = '총점 60점 이상 + 과목별 40% 미만 과락'
 WHERE c.source_exam_code = 'SQLD' AND e.exam_type = 'WRITTEN';

-- ADsP (출처: linkareer ADsP 2026 정리, tilnote ADsP 2027 일정 글 — 데이터자격검정 안내 인용)
UPDATE CERTIFICATION_EXAM_INFO e JOIN CERTIFICATIONS c ON c.certification_id = e.certification_id
   SET e.exam_fee = 50000, e.question_count = 50, e.duration_minutes = 90,
       e.exam_method = 'PBT(지필) · 객관식 (실기 없음)',
       e.pass_criteria = '총점 60점 이상 + 과목별 40% 미만 과락 (데이터 이해 8점·기획 8점·분석 24점 미만)'
 WHERE c.source_exam_code = 'ADSP' AND e.exam_type = 'WRITTEN';

-- 컴활 1급 (출처: foxcg 컴활 1·2급 비교, thewiki 컴활 — 응시료 필기 20,500원·실기 25,000원)
UPDATE CERTIFICATION_EXAM_INFO e JOIN CERTIFICATIONS c ON c.certification_id = e.certification_id
   SET e.exam_fee = 20500, e.question_count = 60, e.duration_minutes = 60,
       e.exam_method = 'CBT · 객관식 (상시시험)', e.pass_criteria = '과목당 40점 이상 + 평균 60점 이상'
 WHERE c.source_exam_code = 'CA1' AND e.exam_type = 'WRITTEN';
UPDATE CERTIFICATION_EXAM_INFO e JOIN CERTIFICATIONS c ON c.certification_id = e.certification_id
   SET e.exam_fee = 25000, e.question_count = NULL, e.duration_minutes = 90,
       e.exam_method = '컴퓨터 작업형 (엑셀 45분 + 액세스 45분)', e.pass_criteria = '두 과목 모두 70점 이상'
 WHERE c.source_exam_code = 'CA1' AND e.exam_type = 'PRACTICAL';

-- 컴활 2급 (출처: 같은 비교 글, yugacrew 컴활 2급 필기 — 대한상의·큐넷 인용)
UPDATE CERTIFICATION_EXAM_INFO e JOIN CERTIFICATIONS c ON c.certification_id = e.certification_id
   SET e.exam_fee = 20500, e.question_count = 40, e.duration_minutes = 40,
       e.exam_method = 'CBT · 객관식 (상시시험)', e.pass_criteria = '과목당 40점 이상 + 평균 60점 이상'
 WHERE c.source_exam_code = 'CA2' AND e.exam_type = 'WRITTEN';
UPDATE CERTIFICATION_EXAM_INFO e JOIN CERTIFICATIONS c ON c.certification_id = e.certification_id
   SET e.exam_fee = 25000, e.question_count = NULL, e.duration_minutes = 40,
       e.exam_method = '컴퓨터 작업형 (엑셀)', e.pass_criteria = '100점 만점에 70점 이상'
 WHERE c.source_exam_code = 'CA2' AND e.exam_type = 'PRACTICAL';

-- 산업안전기사 (출처: glasswallet 안전관리자 자격증 비용 — Q-Net 2026.6 확인 인용, machuda 2026 산안기 필기, kric 자격증정보)
UPDATE CERTIFICATION_EXAM_INFO e JOIN CERTIFICATIONS c ON c.certification_id = e.certification_id
   SET e.exam_fee = 19400, e.question_count = 120, e.duration_minutes = 180,
       e.exam_method = 'CBT · 객관식 4지 택일 (6과목)', e.pass_criteria = '과목당 40점 이상 + 전 과목 평균 60점 이상'
 WHERE c.source_exam_code = 'SAFETY' AND e.exam_type = 'WRITTEN';
UPDATE CERTIFICATION_EXAM_INFO e JOIN CERTIFICATIONS c ON c.certification_id = e.certification_id
   SET e.exam_fee = 34600, e.question_count = NULL, e.duration_minutes = NULL,
       e.exam_method = '복합형: 필답형(1시간, 55점) + 작업형(1시간 정도, 45점)', e.pass_criteria = '100점 만점에 60점 이상'
 WHERE c.source_exam_code = 'SAFETY' AND e.exam_type = 'PRACTICAL';

-- ---------- 응시자격·알아두면 좋은 정보 ----------
UPDATE CERTIFICATION_INFO i JOIN CERTIFICATIONS c ON c.certification_id = i.certification_id
   SET i.eligibility = '학력·경력 요건 있음 (4년제 대학 졸업(예정)자는 학과 무관 등)\n필기 합격 후 응시자격 서류를 기간 안에 내야 함',
       i.eligibility_check_url = 'https://www.q-net.or.kr', i.info_verified_at = '2026-11-26'
 WHERE c.source_exam_code = '1320';
UPDATE CERTIFICATION_INFO i JOIN CERTIFICATIONS c ON c.certification_id = i.certification_id
   SET i.eligibility = '학력·경력 요건 있음 (관련 학과 졸업(예정), 실무 경력 등)\n큐넷 응시자격 자가진단으로 확인',
       i.eligibility_check_url = 'https://www.q-net.or.kr', i.info_verified_at = '2026-11-26'
 WHERE c.source_exam_code = 'SAFETY';
UPDATE CERTIFICATION_INFO i JOIN CERTIFICATIONS c ON c.certification_id = i.certification_id
   SET i.eligibility = '제한 없음', i.validity = '합격 후 2년 지나면 효력 정지, 무료 온라인 보수교육 1회 이수 시 영구',
       i.info_verified_at = '2026-11-26'
 WHERE c.source_exam_code = 'SQLD';
UPDATE CERTIFICATION_INFO i JOIN CERTIFICATIONS c ON c.certification_id = i.certification_id
   SET i.eligibility = '제한 없음', i.validity = '없음 (평생 유효)', i.info_verified_at = '2026-11-26'
 WHERE c.source_exam_code = 'ADSP';
UPDATE CERTIFICATION_INFO i JOIN CERTIFICATIONS c ON c.certification_id = i.certification_id
   SET i.eligibility = '제한 없음', i.written_exemption = '필기 합격일부터 2년 안에 실기 응시',
       i.validity = '없음 (평생 유효)', i.result_notice = '필기: 다음 날 오전 10시 / 실기: 응시 주(수~화) 기준 2주 뒤 화요일 오전 10시',
       i.info_verified_at = '2026-11-26'
 WHERE c.source_exam_code IN ('CA1', 'CA2');
