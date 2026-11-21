-- =====================================================================
-- 03_seed.sql : 기준 데이터 + 테스트용 더미 후기
--   ※ DUMMY 후기는 지어낸 데이터다 (source_id = 4, source_url = example.com).
--     실제 수집 데이터와 구분하고, 지울 때는 04_delete_dummy.sql 실행
--   ※ 실행 순서: 01_schema → 02_schema_ext → 03_seed  (03을 다시 실행하려면 01부터)
-- =====================================================================
USE passpace_merged;

-- 수집 출처 (id 고정: 코드에서 이 번호를 사용)
-- permission_checked_at: 약관·robots.txt·AI 활용 허용 여부를 사람이 확인한 날짜 (기획안 7.1.2)
--   비어 있는 CRAWL 출처는 수집 프로그램이 자동으로 건너뛴다.
--   티스토리는 용성이 확인을 마치면: UPDATE DATA_SOURCES SET permission_checked_at = NOW() WHERE source_id = 7;
INSERT INTO DATA_SOURCES (source_id, source_name, source_type, provider_name, base_url, active_yn, created_at, permission_checked_at) VALUES
 (1, '국가자격 시험일정 조회 API(15074408)', 'API',        '한국산업인력공단', 'https://apis.data.go.kr/B490007/qualExamSchd/getQualExamSchdList', 'Y', NOW(), NULL),
 (2, '샘플 시험일정(실제 일정 아님)',          'SAMPLE',     '패스페이스',       NULL, 'Y', NOW(), NULL),
 (3, 'velog 합격·불합격 후기',                'CRAWL',      'velog',            'https://velog.io', 'Y', NOW(), '2026-11-03 00:00:00'),
 (4, '테스트용 더미 후기(지어낸 데이터)',      'DUMMY',      '패스페이스',       NULL, 'Y', NOW(), NULL),
 (5, '이용자 직접 입력 후기',                  'USER_INPUT', '패스페이스',       NULL, 'Y', NOW(), NULL),
 (6, '공개 학습일지 기반 잠정 추정(소수 사례)', 'PROVISIONAL', '패스페이스',      NULL, 'Y', NOW(), NULL),
 (7, '티스토리 합격·불합격 후기',             'CRAWL',      'tistory',          'https://www.tistory.com', 'Y', NOW(), NULL),
 (8, '데이터 자격검정 시험 정보 API(15062838)', 'API', '한국데이터산업진흥원', 'https://api.odcloud.kr/api/15062838/v1', 'Y', NOW(), NULL);

-- 자격증: 정보처리기사 (종목코드 1320)
INSERT INTO CERTIFICATIONS (certification_id, cert_name, cert_type, issuing_org, source_exam_code, active_yn, pass_criteria) VALUES
 (1, '정보처리기사', '국가기술자격(기사)', '한국산업인력공단', '1320', 'Y',
  '필기: 과목당 40점 이상·전 과목 평균 60점 이상 / 실기: 60점 이상 (큐넷에서 확인 필요)'),
 (2, 'SQLD', '국가공인 민간자격', '한국데이터산업진흥원', 'SQLD', 'Y',
  '과목별 40% 이상·총점 60점 이상 (데이터자격검정 홈페이지에서 확인 필요)');

-- 과목: 2027~2029 출제기준 필기 4과목 + 실기 1과목 (큐넷 출제기준으로 최종 확인 필요)
INSERT INTO CERTIFICATION_SUBJECTS (certification_subject_id, certification_id, subject_name, exam_type, display_order, scope_version, source_id) VALUES
 (1, 1, '소프트웨어 개발',      'WRITTEN',   1, '2027~2029', NULL),
 (2, 1, '데이터베이스 구축',    'WRITTEN',   2, '2027~2029', NULL),
 (3, 1, '프로그래밍 언어 활용', 'WRITTEN',   3, '2027~2029', NULL),
 (4, 1, '정보시스템 구축관리',  'WRITTEN',   4, '2027~2029', NULL),
 (5, 1, '정보처리 실무',        'PRACTICAL', 1, '2027~2029', NULL),
 (6, 2, '데이터 모델링의 이해', 'WRITTEN',   1, '2024~',     NULL),
 (7, 2, 'SQL 기본 및 활용',     'WRITTEN',   2, '2024~',     NULL);

-- 참고 학습시간 잠정값 (기획안 3.2③). 동건이 정리한 공개 학습일지 1~2건 기반이며 평균이 아니다.
-- 용성의 후기 수집 후 [기준 학습시간 갱신]을 실행하면 유효 표본 10건 이상인 조합은 VERIFIED 행이 추가되어 우선 사용된다.
INSERT INTO STUDY_REFERENCE_STATS
 (certification_id, exam_type, certification_subject_id, major_type, mean_hours, min_hours, max_hours, sample_count, base_date,
  stat_status, source_id, source_note, stat_key, updated_at) VALUES
 (1, 'WRITTEN',   NULL, NULL, 23.93, NULL, NULL, 1, '2026-11-07', 'PROVISIONAL', 6, '2026 합격자 1명 일지(구 5과목)를 2027 4과목에 임시 대응. 평균 아님', '1:WRITTEN:ALL:ALL', NOW()),
 (1, 'WRITTEN',   1,    NULL, 11.13, NULL, NULL, 1, '2026-11-07', 'PROVISIONAL', 6, '구 설계 226분+개발 242분 + 공통 기출 비율배분', '1:WRITTEN:1:ALL', NOW()),
 (1, 'WRITTEN',   2,    NULL,  5.71, NULL, NULL, 1, '2026-11-07', 'PROVISIONAL', 6, 'DB 240분 + 공통 기출 비율배분', '1:WRITTEN:2:ALL', NOW()),
 (1, 'WRITTEN',   3,    NULL,  2.78, NULL, NULL, 1, '2026-11-07', 'PROVISIONAL', 6, '언어 117분 + 공통 기출 비율배분', '1:WRITTEN:3:ALL', NOW()),
 (1, 'WRITTEN',   4,    NULL,  4.31, NULL, NULL, 1, '2026-11-07', 'PROVISIONAL', 6, '구축관리 181분 + 공통 기출 비율배분', '1:WRITTEN:4:ALL', NOW()),
 (1, 'PRACTICAL', NULL, NULL, 60.25, NULL, NULL, 1, '2026-11-07', 'PROVISIONAL', 6, '2025 실기 합격 후기 1건 자기보고. 평균 아님', '1:PRACTICAL:ALL:ALL', NOW()),
 (1, 'PRACTICAL', 5,    NULL, 60.25, NULL, NULL, 1, '2026-11-07', 'PROVISIONAL', 6, '실기 단일 과목 = 전체 시간', '1:PRACTICAL:5:ALL', NOW()),
 (2, 'WRITTEN',   NULL, NULL, 19.00, NULL, NULL, 1, '2026-11-07', 'PROVISIONAL', 6, '2026 SQLD 합격자 1명 일지. 평균 아님', '2:WRITTEN:ALL:ALL', NOW()),
 (2, 'WRITTEN',   6,    NULL,  7.60, NULL, NULL, 1, '2026-11-07', 'PROVISIONAL', 6, '모델링 단독 120분 + 공통 840분 비율배분', '2:WRITTEN:6:ALL', NOW()),
 (2, 'WRITTEN',   7,    NULL, 11.40, NULL, NULL, 1, '2026-11-07', 'PROVISIONAL', 6, 'SQL 단독 180분 + 공통 840분 비율배분', '2:WRITTEN:7:ALL', NOW());

-- 더미 후기 48건 (비전공 필기 24, 전공 필기 10, 유사전공 필기 8, 실기 6)
INSERT INTO PASS_REVIEWS
 (source_id, certification_id, exam_type, major_type, source_url, posted_at, proof_yn, prep_days, total_hours, daily_hours,
  study_subjects, evidence_text, review_status, exclude_reason, pass_yn, daily_minutes, exam_year, round_no, study_method) VALUES
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/001', '2026-09-04', 'N', 70, 77.0, '1.5', '소프트웨어 개발', '70일 동안 하루 1시간 30분씩 공부했고 이론보다 기출 풀이에 시간을 대부분 썼다. 소프트웨어 개발 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 90, 2026, 2, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/002', '2026-04-15', 'Y', 80, 227.9, '3', '소프트웨어 개발', '80일 동안 하루 3시간씩 공부했고 이론서를 처음부터 끝까지 정리한 뒤 기출을 풀었다. 소프트웨어 개발 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 180, 2026, 1, 'THEORY'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/003', '2026-10-26', 'Y', 90, 138.3, '2', '데이터베이스 구축', '90일 동안 하루 2시간씩 공부했고 개념은 짧게 훑고 기출문제를 반복해서 풀었다. 데이터베이스 구축 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 120, 2026, 2, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/004', '2025-11-13', 'Y', 95, 186.4, '2.5', '소프트웨어 개발', '95일 동안 하루 2시간 30분씩 공부했고 개념은 짧게 훑고 기출문제를 반복해서 풀었다. 소프트웨어 개발 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 150, 2025, 2, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/005', '2026-03-02', 'N', 100, 287.8, '4', '정보시스템 구축관리', '100일 동안 하루 4시간씩 공부했고 이론보다 기출 풀이에 시간을 대부분 썼다. 정보시스템 구축관리 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 240, 2026, 2, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/006', '2025-03-12', 'N', 110, 257.3, '2.5', '프로그래밍 언어 활용', '110일 동안 하루 2시간 30분씩 공부했고 이론보다 기출 풀이에 시간을 대부분 썼다. 프로그래밍 언어 활용 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 150, 2025, 3, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/007', '2025-04-22', 'N', 120, 317.9, '3', '데이터베이스 구축', '120일 동안 하루 3시간씩 공부했고 개념 정리에 시간을 많이 쓰고 기출은 마지막에 봤다. 데이터베이스 구축 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 180, 2025, 2, 'THEORY'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/008', '2026-10-15', 'Y', 120, 213.8, '2', '정보시스템 구축관리', '120일 동안 하루 2시간씩 공부했고 과목별로 개념을 본 뒤 바로 해당 기출을 풀었다. 정보시스템 구축관리 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 120, 2026, 1, 'BALANCED'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/009', '2025-11-02', 'N', 130, 246.3, '2.5', '소프트웨어 개발', '130일 동안 하루 2시간 30분씩 공부했고 이론서를 처음부터 끝까지 정리한 뒤 기출을 풀었다. 소프트웨어 개발 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 150, 2025, 2, 'THEORY'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/010', '2026-08-07', 'N', 140, 184.1, '1.5', '소프트웨어 개발', '140일 동안 하루 1시간 30분씩 공부했고 이론서를 처음부터 끝까지 정리한 뒤 기출을 풀었다. 소프트웨어 개발 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 90, 2026, 1, 'THEORY'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/011', '2026-05-13', 'Y', 150, 321.3, '2.5', '소프트웨어 개발', '150일 동안 하루 2시간 30분씩 공부했고 과목별로 개념을 본 뒤 바로 해당 기출을 풀었다. 소프트웨어 개발 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 150, 2026, 2, 'BALANCED'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/012', '2025-03-16', 'Y', 160, 333.4, '2.5', '정보시스템 구축관리', '160일 동안 하루 2시간 30분씩 공부했고 개념은 짧게 훑고 기출문제를 반복해서 풀었다. 정보시스템 구축관리 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 150, 2025, 1, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/013', '2025-07-20', 'N', 180, 293.0, '2', '소프트웨어 개발', '180일 동안 하루 2시간씩 공부했고 앞 절반은 이론, 뒤 절반은 기출로 나눠 공부했다. 소프트웨어 개발 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 120, 2025, 3, 'BALANCED'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/014', '2026-06-15', 'N', 60, 90.1, '2', '소프트웨어 개발', '60일 동안 하루 2시간씩 공부했고 개념 정리에 시간을 많이 쓰고 기출은 마지막에 봤다. 소프트웨어 개발 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 120, 2026, 2, 'THEORY'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/015', '2025-09-14', 'Y', 45, 159.0, '4', '프로그래밍 언어 활용', '45일 동안 하루 4시간씩 공부했고 과목별로 개념을 본 뒤 바로 해당 기출을 풀었다. 프로그래밍 언어 활용 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 240, 2025, 3, 'BALANCED'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/016', '2026-02-16', 'N', 30, 67.8, '2.5', '정보시스템 구축관리', '30일 동안 하루 2시간 30분씩 공부했고 최근 기출을 회차별로 세 번 돌렸다. 정보시스템 구축관리 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 150, 2026, 3, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/017', '2025-06-17', 'N', 21, 43.3, '2.5', '프로그래밍 언어 활용', '21일 동안 하루 2시간 30분씩 공부했고 최근 기출을 회차별로 세 번 돌렸다. 프로그래밍 언어 활용 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 150, 2025, 1, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/018', '2025-06-24', 'N', 200, 608.3, '3.5', '프로그래밍 언어 활용', '200일 동안 하루 3시간 30분씩 공부했고 앞 절반은 이론, 뒤 절반은 기출로 나눠 공부했다. 프로그래밍 언어 활용 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 210, 2025, 1, 'BALANCED'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/019', '2026-03-26', 'Y', 90, 107.6, '1.5', '프로그래밍 언어 활용', '90일 동안 하루 1시간 30분씩 준비했지만 프로그래밍 언어 활용 과목에서 과락이 나서 떨어졌다.', 'VALID', NULL, 'N', 90, 2026, 2, 'THEORY'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/020', '2025-06-21', 'Y', 120, 94.8, '1', '소프트웨어 개발', '120일 동안 하루 1시간씩 준비했지만 소프트웨어 개발 과목에서 과락이 나서 떨어졌다.', 'VALID', NULL, 'N', 60, 2025, 2, 'THEORY'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/021', '2026-08-02', 'N', 60, 48.0, '1', '정보시스템 구축관리', '60일 동안 하루 1시간씩 준비했지만 정보시스템 구축관리 과목에서 과락이 나서 떨어졌다.', 'VALID', NULL, 'N', 60, 2026, 2, 'THEORY'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/022', '2026-09-28', 'N', 150, 120.2, '1', '데이터베이스 구축', '150일 동안 하루 1시간씩 준비했지만 데이터베이스 구축 과목에서 과락이 나서 떨어졌다.', 'VALID', NULL, 'N', 60, 2026, 3, 'BALANCED'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/023', '2026-08-16', 'N', 30, 38.3, '1.5', '정보시스템 구축관리', '30일 동안 하루 1시간 30분씩 준비했지만 정보시스템 구축관리 과목에서 과락이 나서 떨어졌다.', 'VALID', NULL, 'N', 90, 2026, 1, 'THEORY'),
(4, 1, 'WRITTEN', 'NON_MAJOR', 'https://example.com/dummy/024', '2026-03-06', 'N', 100, 94.5, '1', '데이터베이스 구축', '100일 동안 하루 1시간씩 준비했지만 데이터베이스 구축 과목에서 과락이 나서 떨어졌다.', 'VALID', NULL, 'N', 60, 2026, 1, 'THEORY'),
(4, 1, 'WRITTEN', 'MAJOR', 'https://example.com/dummy/025', '2026-10-08', 'Y', 7, 6.3, '1', '데이터베이스 구축', '7일 동안 하루 1시간씩 준비했지만 데이터베이스 구축 과목에서 과락이 나서 떨어졌다.', 'VALID', NULL, 'N', 60, 2026, 2, 'BALANCED'),
(4, 1, 'WRITTEN', 'MAJOR', 'https://example.com/dummy/026', '2025-06-13', 'N', 10, 9.1, '1', '프로그래밍 언어 활용', '10일 동안 하루 1시간씩 공부했고 앞 절반은 이론, 뒤 절반은 기출로 나눠 공부했다. 프로그래밍 언어 활용 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 60, 2025, 1, 'BALANCED'),
(4, 1, 'WRITTEN', 'MAJOR', 'https://example.com/dummy/027', '2025-09-01', 'Y', 14, 12.7, '1', '소프트웨어 개발', '14일 동안 하루 1시간씩 공부했고 개념은 짧게 훑고 기출문제를 반복해서 풀었다. 소프트웨어 개발 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 60, 2025, 1, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'MAJOR', 'https://example.com/dummy/028', '2025-10-24', 'N', 14, 26.0, '2', '정보시스템 구축관리', '14일 동안 하루 2시간씩 공부했고 과목별로 개념을 본 뒤 바로 해당 기출을 풀었다. 정보시스템 구축관리 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 120, 2025, 3, 'BALANCED'),
(4, 1, 'WRITTEN', 'MAJOR', 'https://example.com/dummy/029', '2025-05-11', 'N', 20, 34.8, '2', '정보시스템 구축관리', '20일 동안 하루 2시간씩 공부했고 최근 기출을 회차별로 세 번 돌렸다. 정보시스템 구축관리 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 120, 2025, 1, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'MAJOR', 'https://example.com/dummy/030', '2026-02-01', 'Y', 30, 68.9, '3', '정보시스템 구축관리', '30일 동안 하루 3시간씩 공부했고 최근 기출을 회차별로 세 번 돌렸다. 정보시스템 구축관리 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 180, 2026, 3, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'MAJOR', 'https://example.com/dummy/031', '2026-09-03', 'N', 30, 74.2, '3', '정보시스템 구축관리', '30일 동안 하루 3시간씩 공부했고 최근 기출을 회차별로 세 번 돌렸다. 정보시스템 구축관리 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 180, 2026, 3, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'MAJOR', 'https://example.com/dummy/032', '2026-03-01', 'N', 45, 67.0, '2', '정보시스템 구축관리', '45일 동안 하루 2시간씩 공부했고 개념은 짧게 훑고 기출문제를 반복해서 풀었다. 정보시스템 구축관리 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 120, 2026, 1, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'MAJOR', 'https://example.com/dummy/033', '2026-05-17', 'N', 60, 166.7, '3', '프로그래밍 언어 활용', '60일 동안 하루 3시간씩 공부했고 과목별로 개념을 본 뒤 바로 해당 기출을 풀었다. 프로그래밍 언어 활용 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 180, 2026, 1, 'BALANCED'),
(4, 1, 'WRITTEN', 'MAJOR', 'https://example.com/dummy/034', '2026-06-12', 'N', 90, 168.2, '2', '프로그래밍 언어 활용', '90일 동안 하루 2시간씩 공부했고 개념은 짧게 훑고 기출문제를 반복해서 풀었다. 프로그래밍 언어 활용 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 120, 2026, 1, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'RELATED', 'https://example.com/dummy/035', '2026-03-20', 'Y', 21, 45.3, '2.5', '프로그래밍 언어 활용', '21일 동안 하루 2시간 30분씩 공부했고 최근 기출을 회차별로 세 번 돌렸다. 프로그래밍 언어 활용 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 150, 2026, 2, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'RELATED', 'https://example.com/dummy/036', '2026-09-24', 'Y', 30, 57.8, '2.5', '소프트웨어 개발', '30일 동안 하루 2시간 30분씩 공부했고 과목별로 개념을 본 뒤 바로 해당 기출을 풀었다. 소프트웨어 개발 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 150, 2026, 2, 'BALANCED'),
(4, 1, 'WRITTEN', 'RELATED', 'https://example.com/dummy/037', '2025-09-03', 'Y', 45, 67.2, '2', '정보시스템 구축관리', '45일 동안 하루 2시간씩 공부했고 최근 기출을 회차별로 세 번 돌렸다. 정보시스템 구축관리 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 120, 2025, 3, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'RELATED', 'https://example.com/dummy/038', '2026-10-23', 'Y', 60, 110.1, '2.5', '소프트웨어 개발', '60일 동안 하루 2시간 30분씩 공부했고 이론보다 기출 풀이에 시간을 대부분 썼다. 소프트웨어 개발 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 150, 2026, 3, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'RELATED', 'https://example.com/dummy/039', '2026-05-20', 'Y', 60, 105.4, '2.5', '데이터베이스 구축', '60일 동안 하루 2시간 30분씩 공부했고 최근 기출을 회차별로 세 번 돌렸다. 데이터베이스 구축 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 150, 2026, 3, 'PAST_EXAM'),
(4, 1, 'WRITTEN', 'RELATED', 'https://example.com/dummy/040', '2026-08-21', 'Y', 90, 107.5, '1.5', '데이터베이스 구축', '90일 동안 하루 1시간 30분씩 공부했고 앞 절반은 이론, 뒤 절반은 기출로 나눠 공부했다. 데이터베이스 구축 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 90, 2026, 1, 'BALANCED'),
(4, 1, 'WRITTEN', 'RELATED', 'https://example.com/dummy/041', '2026-02-26', 'N', 120, 158.3, '1.5', '정보시스템 구축관리', '120일 동안 하루 1시간 30분씩 공부했고 앞 절반은 이론, 뒤 절반은 기출로 나눠 공부했다. 정보시스템 구축관리 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 90, 2026, 3, 'BALANCED'),
(4, 1, 'WRITTEN', 'RELATED', 'https://example.com/dummy/042', '2026-03-06', 'N', 40, 49.1, '1.5', '데이터베이스 구축', '40일 동안 하루 1시간 30분씩 준비했지만 데이터베이스 구축 과목에서 과락이 나서 떨어졌다.', 'VALID', NULL, 'N', 90, 2026, 1, 'PAST_EXAM'),
(4, 1, 'PRACTICAL', 'NON_MAJOR', 'https://example.com/dummy/043', '2026-11-18', 'Y', 30, 63.8, '2.5', '프로그래밍 언어 활용', '30일 동안 하루 2시간 30분씩 공부했고 이론보다 기출 풀이에 시간을 대부분 썼다. 프로그래밍 언어 활용 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 150, 2026, 1, 'PAST_EXAM'),
(4, 1, 'PRACTICAL', 'NON_MAJOR', 'https://example.com/dummy/044', '2025-06-27', 'Y', 45, 141.6, '4', '정보시스템 구축관리', '45일 동안 하루 4시간씩 공부했고 이론보다 기출 풀이에 시간을 대부분 썼다. 정보시스템 구축관리 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 240, 2025, 1, 'PAST_EXAM'),
(4, 1, 'PRACTICAL', 'MAJOR', 'https://example.com/dummy/045', '2026-09-26', 'N', 60, 139.7, '2.5', '프로그래밍 언어 활용', '60일 동안 하루 2시간 30분씩 공부했고 이론보다 기출 풀이에 시간을 대부분 썼다. 프로그래밍 언어 활용 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 150, 2026, 3, 'PAST_EXAM'),
(4, 1, 'PRACTICAL', 'MAJOR', 'https://example.com/dummy/046', '2026-09-24', 'Y', 21, 63.6, '4', '데이터베이스 구축', '21일 동안 하루 4시간씩 공부했고 최근 기출을 회차별로 세 번 돌렸다. 데이터베이스 구축 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 240, 2026, 2, 'PAST_EXAM'),
(4, 1, 'PRACTICAL', 'RELATED', 'https://example.com/dummy/047', '2026-08-12', 'N', 40, 149.6, '4', '데이터베이스 구축', '40일 동안 하루 4시간씩 공부했고 이론보다 기출 풀이에 시간을 대부분 썼다. 데이터베이스 구축 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 240, 2026, 2, 'PAST_EXAM'),
(4, 1, 'PRACTICAL', 'NON_MAJOR', 'https://example.com/dummy/048', '2025-09-13', 'Y', 50, 100.9, '2.5', '프로그래밍 언어 활용', '50일 동안 하루 2시간 30분씩 공부했고 최근 기출을 회차별로 세 번 돌렸다. 프로그래밍 언어 활용 과목이 가장 어려웠다.', 'VALID', NULL, 'Y', 150, 2025, 1, 'PAST_EXAM');

SELECT COUNT(*) AS dummy_reviews FROM PASS_REVIEWS WHERE source_id = 4;
