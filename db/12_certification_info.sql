-- =====================================================================
-- [11-26] 지원 자격증 정보 메뉴 (앱 홈 "지원 자격증" → 목록 → 상세)
--   기존 표는 바꾸지 않고 새 표 2개만 만든다.
--   (배포 DB 는 칸 이름 없이 값만 넣는 덤프 90_passpace_data.sql 로 채우므로, 기존 표 칸 수가 바뀌면 덤프가 실패한다)
--   실행 순서: 01 ~ 11 다음. 모의/학교 서버 initdb 에도 12 로 넣으면 90 보다 먼저 실행된다 (새 표라 충돌 없음)
--
--   값 원칙: 공식 사이트에서 확인한 값만 넣는다. 확인 못 한 칸은 NULL → 앱은 "공식 사이트에서 확인" 으로 보여 준다.
--   응시료·문항 수·시험시간·응시자격은 아직 확인 전이라 비워 둔다 (공식 값 조사 담당이 채움, 아래 템플릿 참고).
-- =====================================================================

CREATE TABLE IF NOT EXISTS CERTIFICATION_INFO (
  certification_id       BIGINT        NOT NULL,
  grade                  VARCHAR(30)   NULL COMMENT '등급 (기사, 1급, 2급 ...)',
  category               VARCHAR(20)   NULL COMMENT '분야: IT / 데이터 / 사무·회계 / 안전',
  summary                VARCHAR(300)  NULL COMMENT '한 줄 소개',
  eligibility            VARCHAR(500)  NULL COMMENT '응시자격 (줄바꿈으로 항목 구분, 없으면 제한 없음)',
  eligibility_check_url  VARCHAR(500)  NULL COMMENT '응시자격 자가진단 링크',
  always_open_yn         CHAR(1)       NOT NULL DEFAULT 'N' COMMENT '상시 시험 여부 (회차 없음)',
  written_exemption      VARCHAR(200)  NULL COMMENT '필기 면제 규정',
  required_items         VARCHAR(300)  NULL COMMENT '준비물',
  validity               VARCHAR(100)  NULL COMMENT '자격 유효기간',
  refund_note            VARCHAR(300)  NULL COMMENT '접수 취소·환불 요약',
  refund_url             VARCHAR(500)  NULL,
  result_notice          VARCHAR(200)  NULL COMMENT '합격 발표 방법',
  related_certs          VARCHAR(200)  NULL COMMENT '관련 자격 (표시용 문장)',
  official_url           VARCHAR(500)  NULL COMMENT '공식 안내',
  apply_url              VARCHAR(500)  NULL COMMENT '원서 접수',
  info_verified_at       DATE          NULL COMMENT '공식 사이트에서 값을 확인한 날',
  PRIMARY KEY (certification_id),
  CONSTRAINT fk_cert_info_cert FOREIGN KEY (certification_id) REFERENCES CERTIFICATIONS (certification_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS CERTIFICATION_EXAM_INFO (
  certification_exam_info_id  BIGINT        NOT NULL AUTO_INCREMENT,
  certification_id            BIGINT        NOT NULL,
  exam_type                   VARCHAR(30)   NOT NULL COMMENT 'WRITTEN / PRACTICAL',
  exam_fee                    INT           NULL COMMENT '응시료 (원)',
  question_count              INT           NULL,
  duration_minutes            INT           NULL,
  exam_method                 VARCHAR(200)  NULL COMMENT '예: CBT · 객관식 4지 택일',
  pass_criteria               VARCHAR(200)  NULL COMMENT '과목별 과락 포함',
  scope_year                  SMALLINT      NULL COMMENT '출제기준 적용 연도',
  PRIMARY KEY (certification_exam_info_id),
  UNIQUE KEY UK_CERT_EXAM_INFO (certification_id, exam_type),
  CONSTRAINT fk_cert_exam_info_cert FOREIGN KEY (certification_id) REFERENCES CERTIFICATIONS (certification_id)
) ENGINE=InnoDB;

-- 기존 4종: 확실한 값만 (공식 사이트 주소, 분야, 상시 여부, 국가기술자격 공통 규정)
INSERT INTO CERTIFICATION_INFO (certification_id, grade, category, summary, always_open_yn, written_exemption, validity,
                                related_certs, official_url, apply_url)
SELECT c.certification_id, v.grade, v.category, v.summary, v.always_open_yn, v.written_exemption, v.validity,
       v.related_certs, v.official_url, v.apply_url
FROM CERTIFICATIONS c
JOIN (
  SELECT '1320' AS code, '기사' AS grade, 'IT' AS category,
         '소프트웨어 개발·데이터베이스·정보시스템 기초를 다루는 IT 대표 국가기술자격' AS summary, 'N' AS always_open_yn,
         '필기 합격 발표일부터 2년간 필기 면제' AS written_exemption, '없음 (갱신 불필요)' AS validity,
         'SQLD, 정보처리산업기사' AS related_certs, 'https://www.q-net.or.kr' AS official_url, 'https://www.q-net.or.kr' AS apply_url
  UNION ALL SELECT 'SQLD', NULL, '데이터', 'SQL 활용 능력을 검정하는 데이터 분야 입문 자격', 'N', NULL, NULL,
         'SQLP, ADsP', 'https://www.dataq.or.kr', 'https://www.dataq.or.kr'
  UNION ALL SELECT 'CA1', '1급', '사무·회계', '스프레드시트·데이터베이스 활용 능력을 검정하는 사무 자격', 'Y',
         NULL, NULL, '컴퓨터활용능력 2급', 'https://license.korcham.net', 'https://license.korcham.net'
  UNION ALL SELECT 'ADSP', NULL, '데이터', '데이터 분석 기획·통계 기초를 검정하는 데이터 분야 입문 자격', 'N', NULL, NULL,
         '빅데이터분석기사, SQLD', 'https://www.dataq.or.kr', 'https://www.dataq.or.kr'
) v ON v.code = c.source_exam_code
ON DUPLICATE KEY UPDATE grade = VALUES(grade), category = VALUES(category), summary = VALUES(summary),
  always_open_yn = VALUES(always_open_yn), written_exemption = VALUES(written_exemption), validity = VALUES(validity),
  related_certs = VALUES(related_certs), official_url = VALUES(official_url), apply_url = VALUES(apply_url);

-- 시험 구분별 정보: 행만 만들고 값은 비워 둔다 (합격 기준은 CERTIFICATIONS.pass_criteria 를 API 가 대신 보여 줌)
INSERT IGNORE INTO CERTIFICATION_EXAM_INFO (certification_id, exam_type)
SELECT c.certification_id, t.exam_type
FROM CERTIFICATIONS c
JOIN (SELECT 'WRITTEN' AS exam_type UNION ALL SELECT 'PRACTICAL') t
WHERE c.source_exam_code IN ('1320', 'CA1')
   OR (c.source_exam_code IN ('SQLD', 'ADSP') AND t.exam_type = 'WRITTEN');

-- ---------------------------------------------------------------------
-- 공식 값 입력 템플릿 (확인 후 주석을 풀고 값·출처·확인일을 채운다)
-- UPDATE CERTIFICATION_EXAM_INFO e JOIN CERTIFICATIONS c ON c.certification_id = e.certification_id
--    SET e.exam_fee = ?, e.question_count = ?, e.duration_minutes = ?, e.exam_method = ?, e.pass_criteria = ?
--  WHERE c.source_exam_code = '1320' AND e.exam_type = 'WRITTEN';   -- 출처: https://www.q-net.or.kr ... (확인일)
-- UPDATE CERTIFICATION_INFO i JOIN CERTIFICATIONS c ON c.certification_id = i.certification_id
--    SET i.eligibility = ?, i.required_items = ?, i.refund_note = ?, i.result_notice = ?, i.info_verified_at = '2026-11-xx'
--  WHERE c.source_exam_code = '1320';
-- 참고(확인 필요, 11-24 조사값): 산업안전기사 응시료 필기 19,400 / 실기 34,600, 전산회계 1급 30,000
-- ---------------------------------------------------------------------
