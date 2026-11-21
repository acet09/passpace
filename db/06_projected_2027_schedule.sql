-- =====================================================================
-- [용성·3차] 2027년 "예상" 시험일정 더미 데이터 (공식 일정 아님)
--
-- 만드는 방법
--   - 공식 API 로 수집한 2026년 일정(source_id 1 = 큐넷 정처기, 8 = SQLD)을 복사해 2027년 행을 만든다
--   - 날짜는 364일(=52주) 뒤로 옮긴다 → 요일이 그대로 유지된다 (2026-03-07 토 → 2027-03-06 토)
--   - 회차: 정처기는 같은 회차(1·2·3회), SQLD 는 회차 번호가 이어지므로 +4 (60~63회 → 64~67회)
--   - source_id = 2 (SAMPLE, "샘플 시험일정(실제 일정 아님)") 로 저장 → 화면에 "샘플" 표시가 붙는다
--
-- 실제 2027년 일정이 공고되면
--   - 관리자 화면에서 시험일정 수집 버튼을 누르면 같은 회차 행을 실제 날짜·출처(1 또는 8)로 덮어쓴다
--   - 바뀐 날짜는 EXAM_SCHEDULE_CHANGE_LOGS 에 남는다
--
-- 실행 전 조건: 관리자 화면에서 정처기·SQLD 시험일정 수집을 먼저 실행해 2026년 실제 일정이 있어야 한다
-- 여러 번 실행해도 안전하다 (이미 있는 2027년 행은 건너뜀). DBeaver 에서는 Alt+X(스크립트 실행)
-- =====================================================================
USE passpace_merged;

INSERT IGNORE INTO EXAM_ROUNDS (
    certification_id, source_id, source_exam_code, exam_year, round_no, exam_type,
    reg_start_at, reg_end_at, add_reg_start_at, add_reg_end_at,
    exam_date, exam_start_date, exam_end_date, result_date, last_synced_at)
SELECT r.certification_id,
       2,                                                     -- SAMPLE (실제 일정 아님)
       r.source_exam_code,
       r.exam_year + 1,
       CASE WHEN r.source_id = 8 THEN r.round_no + 4 ELSE r.round_no END,
       r.exam_type,
       DATE_ADD(r.reg_start_at,     INTERVAL 364 DAY),
       DATE_ADD(r.reg_end_at,       INTERVAL 364 DAY),
       DATE_ADD(r.add_reg_start_at, INTERVAL 364 DAY),
       DATE_ADD(r.add_reg_end_at,   INTERVAL 364 DAY),
       DATE_ADD(r.exam_date,        INTERVAL 364 DAY),
       DATE_ADD(r.exam_start_date,  INTERVAL 364 DAY),
       DATE_ADD(r.exam_end_date,    INTERVAL 364 DAY),
       DATE_ADD(r.result_date,      INTERVAL 364 DAY),
       NOW()
FROM EXAM_ROUNDS r
WHERE r.exam_year = 2026
  AND r.source_id IN (1, 8);                                 -- 공식 API 로 수집한 행만 복사

-- 확인: 2026 실제(API) ↔ 2027 예상(SAMPLE), 요일이 같아야 한다
SELECT c.cert_name AS 자격증, r.exam_year AS 연도, r.round_no AS 회차, r.exam_type AS 구분,
       r.exam_start_date AS 시험일, DAYNAME(r.exam_start_date) AS 요일,
       DATE(r.reg_start_at) AS 접수시작, r.result_date AS 발표일, d.source_type AS 출처
FROM EXAM_ROUNDS r
JOIN CERTIFICATIONS c ON c.certification_id = r.certification_id
JOIN DATA_SOURCES d ON d.source_id = r.source_id
WHERE r.exam_year IN (2026, 2027)
ORDER BY c.certification_id, r.exam_type, r.exam_year, r.round_no;

-- 되돌리기 (예상 일정만 삭제):
-- DELETE FROM EXAM_ROUNDS WHERE exam_year = 2027 AND source_id = 2;
