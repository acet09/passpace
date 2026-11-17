-- =====================================================================
-- [용성·11-16] 후기별 과목 언급 테이블 (REVIEW_SUBJECT_MENTIONS) — 팀 합의용 초안
--
-- 왜 필요한가
--   - STUDY_REFERENCE_STATS 의 과목별 값은 합격자 1명의 일지로 넣은 잠정값(PROVISIONAL)이다
--   - 크롤링 후기로 과목별 평균을 내려면, 후기 1편마다 과목별 값을 먼저 모아 둘 곳이 필요하다
--     (PASS_REVIEWS 에는 과목 이름 목록(study_subjects)만 있고 과목별 시간 칸이 없음)
--   - 이 테이블 = 후기 1편 × 과목 1개 × 언급 종류 1개 = 1줄
--   - 값은 SubjectStudyExtractor(용성)가 뽑고, 과목별 평균은 StudyReferenceAggregator 가
--     STUDY_REFERENCE_STATS 에 과목 ID 가 들어간 줄로 저장한다 → 동건·한결은 이 테이블을 읽지 않는다
--
-- 규칙 (DB 계약과 같음)
--   - 시간 단위는 이름에 표시(study_hours = 시간), 모르면 NULL(0과 구분), 코드값은 영문 대문자
--   - 원문은 저장하지 않는다. evidence_text 는 뽑은 값으로 만든 요약문
--   - 후기를 지우면(DELETE FROM PASS_REVIEWS ...) 이 테이블의 줄도 자동으로 지워진다 (ON DELETE CASCADE)
--     → 지금 코드의 후기 삭제(JdbcPassReviewRepository, db/04)는 모두 DELETE 라서 그대로 동작한다
--   - 여러 번 실행해도 안전하다 (IF NOT EXISTS)
--
-- 실행: DBeaver 에서 passpace_merged 연결 → 이 파일 전체 실행(Alt+X)
--   ※ 셋 합의 전에는 각자 실행하지 않아도 된다. 아직 이 테이블을 쓰는 코드가 없어서 서버는 그대로 동작한다
-- =====================================================================
USE passpace_merged;

CREATE TABLE IF NOT EXISTS REVIEW_SUBJECT_MENTIONS (
  mention_id                BIGINT        NOT NULL AUTO_INCREMENT COMMENT '줄 번호',
  review_id                 BIGINT        NOT NULL COMMENT '후기 (PASS_REVIEWS)',
  certification_subject_id  BIGINT        NULL     COMMENT '과목 번호. 2027 출제기준에 없는 옛 과목(소프트웨어 설계)은 NULL',
  subject_name              VARCHAR(100)  NOT NULL COMMENT '과목명 (CERTIFICATION_SUBJECTS.subject_name 표기, 옛 과목은 이름 그대로)',
  mention_type              VARCHAR(20)   NOT NULL COMMENT 'HOURS 시간 / RATIO 비율 / SKIPPED 건너뜀 / DIFFICULT 어려움 / EASY 쉬움',
  study_hours               DECIMAL(6,2)  NULL     COMMENT '과목 공부시간(시간). HOURS·SKIPPED(0) 일 때만',
  hours_ratio               DECIMAL(5,2)  NULL     COMMENT '전체 공부시간 중 비율(%). RATIO 일 때만',
  estimated_yn              CHAR(1)       NOT NULL DEFAULT 'N' COMMENT 'Y = 일수 × 하루 공부시간처럼 환산한 값',
  evidence_text             VARCHAR(500)  NULL     COMMENT '근거 요약문 (원문 아님)',
  created_at                DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '저장 시각',
  PRIMARY KEY (mention_id),
  UNIQUE KEY UK_REVIEW_SUBJECT_MENTION (review_id, subject_name, mention_type),
  KEY IX_RSM_SUBJECT (certification_subject_id, mention_type),
  CONSTRAINT fk_rsm_review  FOREIGN KEY (review_id)                REFERENCES PASS_REVIEWS (review_id) ON DELETE CASCADE,
  CONSTRAINT fk_rsm_subject FOREIGN KEY (certification_subject_id) REFERENCES CERTIFICATION_SUBJECTS (certification_subject_id),
  CONSTRAINT ck_rsm_type    CHECK (mention_type IN ('HOURS', 'RATIO', 'SKIPPED', 'DIFFICULT', 'EASY')),
  CONSTRAINT ck_rsm_hours   CHECK (study_hours IS NULL OR study_hours BETWEEN 0 AND 999),
  CONSTRAINT ck_rsm_ratio   CHECK (hours_ratio IS NULL OR hours_ratio BETWEEN 0 AND 100),
  CONSTRAINT ck_rsm_est     CHECK (estimated_yn IN ('Y', 'N'))
) ENGINE=InnoDB COMMENT='후기별 과목 언급 (후기 1편 × 과목 1개 × 언급 종류 1개)';

-- 확인
SELECT COUNT(*) AS rows_now FROM REVIEW_SUBJECT_MENTIONS;
