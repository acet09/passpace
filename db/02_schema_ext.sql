-- =====================================================================
-- 02_schema_ext.sql : passpace_erd.sql 위에 이번 실험 기능에 필요한 확장 컬럼만 추가 (기존 컬럼은 건드리지 않음)
--   여러 번 실행해도 안전하다 (IF NOT EXISTS)
-- =====================================================================
USE passpace_merged;

-- [한결] 아이디 로그인을 위해 login_id 추가 (이메일 중복 방지는 passpace_erd.sql 의 uk_users_email 사용)
ALTER TABLE `USERS`
  ADD COLUMN IF NOT EXISTS `login_id` VARCHAR(30) NULL COMMENT '로그인 아이디 (확장)' AFTER `user_id`,
  ADD UNIQUE INDEX IF NOT EXISTS `UK_USERS_LOGIN_ID` (`login_id`);

-- [한결] 하루 가용 학습시간. ERD에는 STUDY_PLANS.weekday_minutes(요일별)만 있어 목표 단계에서 받을 곳이 없음
ALTER TABLE `USER_GOALS`
  ADD COLUMN IF NOT EXISTS `daily_minutes` INT NULL COMMENT '하루 가용 학습시간(분) (확장)';

-- [용성] 후기 통계에 필요한 값
--   pass_yn       : 합격/불합격 구분 (ERD에 없음, 불합격 후기도 비교 자료로 수집)
--   daily_minutes : 하루 공부시간 숫자(분). 원본 daily_hours(VARCHAR)는 표시용으로 유지
--   exam_year, round_no : 응시 연도·회차 (공식 일정과 대조용)
--   study_method  : THEORY(이론 위주) / PAST_EXAM(기출 위주) / BALANCED(병행)
--   collected_at  : 수집 일시
--   author_hash   : 작성자 해시 (기획안 7.1.3 같은 작성자 1표본 · 7.1.4 작성자 ID 저장 금지)
--   ※ posted_at(원본 ERD) 에 글 작성일을 저장해 "최근 3년" 조건을 확인한다
ALTER TABLE `PASS_REVIEWS`
  ADD COLUMN IF NOT EXISTS `pass_yn` CHAR(1) NULL COMMENT '합격 여부 Y/N (확장)',
  ADD COLUMN IF NOT EXISTS `daily_minutes` INT NULL COMMENT '하루 공부시간(분) (확장)',
  ADD COLUMN IF NOT EXISTS `exam_year` INT NULL COMMENT '응시 연도 (확장)',
  ADD COLUMN IF NOT EXISTS `round_no` INT NULL COMMENT '응시 회차 (확장)',
  ADD COLUMN IF NOT EXISTS `study_method` VARCHAR(30) NULL COMMENT '학습 방식 THEORY/PAST_EXAM/BALANCED (확장)',
  ADD COLUMN IF NOT EXISTS `collected_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP COMMENT '수집 일시 (확장)',
  ADD COLUMN IF NOT EXISTS `author_hash` CHAR(64) NULL COMMENT '작성자 해시 SHA-256 (아이디 원본 저장 안 함, 같은 작성자 1표본) (확장)',
  ADD UNIQUE INDEX IF NOT EXISTS `UK_PASS_REVIEWS_URL` (`source_url`),
  ADD INDEX IF NOT EXISTS `IX_PASS_REVIEWS_AUTHOR` (`author_hash`);

-- [용성] 합격률 API(15089380) 값을 저장할 곳 + 같은 회차 중복 저장 방지
ALTER TABLE `EXAM_ROUNDS`
  ADD COLUMN IF NOT EXISTS `applicant_count` INT NULL COMMENT '응시자 수 (확장)',
  ADD COLUMN IF NOT EXISTS `pass_count` INT NULL COMMENT '합격자 수 (확장)',
  ADD COLUMN IF NOT EXISTS `pass_rate` DECIMAL(5,2) NULL COMMENT '합격률 % (확장)',
  ADD UNIQUE INDEX IF NOT EXISTS `UK_EXAM_ROUNDS_ROUND` (`certification_id`, `exam_year`, `round_no`, `exam_type`);

-- [용성] 합격 기준 문장 (자격정보 API 15003003 또는 수동 입력)
ALTER TABLE `CERTIFICATIONS`
  ADD COLUMN IF NOT EXISTS `pass_criteria` VARCHAR(200) NULL COMMENT '합격 기준 (확장)';

-- [용성] 수집 정책: 출처별 수집·AI 활용 허용 여부 확인 날짜
ALTER TABLE `DATA_SOURCES`
  ADD COLUMN IF NOT EXISTS `permission_checked_at` DATETIME NULL COMMENT '수집 허용 여부 확인 일시 (확장)';

-- [공통·병합 2차] 참고 학습시간 (기획안 3.2③ · 7.1.4)
--  한 행 = (자격증, 시험구분, 과목[NULL=자격증 전체], 전공[NULL=전체]) 의 참고 학습시간
--  stat_status: PROVISIONAL(소수 공개 사례 기반 잠정값) / VERIFIED(합격 후기 유효 표본 10건 이상 실측 평균)
--  stat_key   : 위 4개 조합을 문자열로 만든 중복 방지 키 (NULL 이 섞인 UNIQUE 대신 사용)
ALTER TABLE `STUDY_REFERENCE_STATS`
  ADD COLUMN IF NOT EXISTS `certification_subject_id` BIGINT NULL COMMENT '과목 (NULL=자격증 전체) (확장)',
  ADD COLUMN IF NOT EXISTS `major_type` VARCHAR(30) NULL COMMENT '전공 구분 (NULL=전체) (확장)',
  ADD COLUMN IF NOT EXISTS `stat_status` VARCHAR(30) NOT NULL DEFAULT 'PROVISIONAL' COMMENT 'PROVISIONAL/VERIFIED (확장)',
  ADD COLUMN IF NOT EXISTS `source_id` BIGINT NULL COMMENT '근거 출처 (확장)',
  ADD COLUMN IF NOT EXISTS `source_note` VARCHAR(500) NULL COMMENT '산출 근거·한계 (확장)',
  ADD COLUMN IF NOT EXISTS `stat_key` VARCHAR(120) NULL COMMENT '중복 방지 키 (확장)',
  ADD COLUMN IF NOT EXISTS `updated_at` DATETIME NULL COMMENT '갱신 일시 (확장)',
  ADD UNIQUE INDEX IF NOT EXISTS `UK_REF_STATS_KEY` (`stat_key`);
