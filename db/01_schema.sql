-- =====================================================================
-- 01_schema.sql = passpace_erd.sql (팀 기준 ERD DDL, 20개 테이블) 그대로
--   실행 순서: 01_schema(이 파일) → 02_schema_ext → 03_seed
-- =====================================================================
-- =====================================================================
-- PASS_PACE ERD (기획안 1104 기준, 20개 테이블) - MariaDB DDL
-- DBeaver: 이 파일을 SQL 편집기에 열고 "스크립트 실행"(Alt+X)
-- 실행 후 데이터베이스 passpace_merged → 우클릭 → "View Diagram" 으로 ERD 확인
-- 다시 실행하면 기존 테이블을 모두 지우고 새로 만든다 (데이터도 삭제됨)
-- =====================================================================
CREATE DATABASE IF NOT EXISTS passpace_merged CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE passpace_merged;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS AI_PLAN_PROPOSALS, CHAT_MESSAGES, CHAT_CONVERSATIONS, STUDY_SESSIONS,
  STUDY_PLAN_DETAILS, PLAN_GOALS, STUDY_PLANS, GOAL_SUBJECTS, USER_GOALS, USERS, PASS_REVIEWS,
  STUDY_REFERENCE_STATS, EXAM_SCHEDULE_CHANGE_LOGS, EXAM_ROUNDS, CERT_RELATIONS, SUBJECT_LINKS,
  CERTIFICATION_SUBJECTS, CERTIFICATIONS, DATA_SYNC_JOBS, DATA_SOURCES;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- 1. 수집 출처
-- ---------------------------------------------------------------------
CREATE TABLE DATA_SOURCES (
  source_id      BIGINT        NOT NULL AUTO_INCREMENT,
  source_name    VARCHAR(100)  NOT NULL,
  source_type    VARCHAR(30)   NULL,
  provider_name  VARCHAR(100)  NULL,
  base_url       VARCHAR(500)  NULL,
  active_yn      CHAR(1)       NOT NULL DEFAULT 'Y',
  created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (source_id)
) ENGINE=InnoDB;

CREATE TABLE DATA_SYNC_JOBS (
  sync_log_id    BIGINT        NOT NULL AUTO_INCREMENT,
  source_id      BIGINT        NOT NULL,
  sync_target    VARCHAR(100)  NULL,
  started_at     DATETIME      NULL,
  ended_at       DATETIME      NULL,
  success_count  INT           NULL,
  failed_count   INT           NULL,
  skipped_count  INT           NULL,
  status         VARCHAR(30)   NULL,
  fail_type      VARCHAR(100)  NULL,
  error_message  TEXT          NULL,
  PRIMARY KEY (sync_log_id),
  CONSTRAINT fk_sync_jobs_source FOREIGN KEY (source_id) REFERENCES DATA_SOURCES (source_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. 자격증 · 과목
-- ---------------------------------------------------------------------
CREATE TABLE CERTIFICATIONS (
  certification_id  BIGINT        NOT NULL AUTO_INCREMENT,
  cert_name         VARCHAR(150)  NOT NULL,
  cert_type         VARCHAR(50)   NULL,
  issuing_org       VARCHAR(100)  NULL,
  source_exam_code  VARCHAR(80)   NULL,
  active_yn         CHAR(1)       NOT NULL DEFAULT 'Y',
  PRIMARY KEY (certification_id)
) ENGINE=InnoDB;

CREATE TABLE CERTIFICATION_SUBJECTS (
  certification_subject_id  BIGINT        NOT NULL AUTO_INCREMENT,
  certification_id          BIGINT        NOT NULL,
  subject_name              VARCHAR(150)  NOT NULL,
  exam_type                 VARCHAR(30)   NULL,
  base_hours                DECIMAL(8,2)  NULL,
  no_base_hours             DECIMAL(8,2)  NULL,
  display_order             INT           NULL,
  scope_version             VARCHAR(80)   NULL,
  official_reference_url    VARCHAR(500)  NULL,
  source_id                 BIGINT        NULL,
  verified_at               DATETIME      NULL,
  PRIMARY KEY (certification_subject_id),
  CONSTRAINT fk_cert_subjects_cert   FOREIGN KEY (certification_id) REFERENCES CERTIFICATIONS (certification_id),
  CONSTRAINT fk_cert_subjects_source FOREIGN KEY (source_id)        REFERENCES DATA_SOURCES (source_id)
) ENGINE=InnoDB;

CREATE TABLE SUBJECT_LINKS (
  link_id            BIGINT        NOT NULL AUTO_INCREMENT,
  subject_id         BIGINT        NOT NULL,
  linked_subject_id  BIGINT        NOT NULL,
  link_note          VARCHAR(200)  NULL,
  created_at         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (link_id),
  CONSTRAINT fk_subject_links_subject FOREIGN KEY (subject_id)        REFERENCES CERTIFICATION_SUBJECTS (certification_subject_id),
  CONSTRAINT fk_subject_links_linked  FOREIGN KEY (linked_subject_id) REFERENCES CERTIFICATION_SUBJECTS (certification_subject_id)
) ENGINE=InnoDB;

CREATE TABLE CERT_RELATIONS (
  relation_id       BIGINT       NOT NULL AUTO_INCREMENT,
  certification_id  BIGINT       NOT NULL,
  related_cert_id   BIGINT       NOT NULL,
  relation_type     VARCHAR(30)  NULL,
  rank_no           INT          NULL,
  source_id         BIGINT       NULL,
  sample_count      INT          NULL,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (relation_id),
  CONSTRAINT fk_cert_rel_cert    FOREIGN KEY (certification_id) REFERENCES CERTIFICATIONS (certification_id),
  CONSTRAINT fk_cert_rel_related FOREIGN KEY (related_cert_id)  REFERENCES CERTIFICATIONS (certification_id),
  CONSTRAINT fk_cert_rel_source  FOREIGN KEY (source_id)        REFERENCES DATA_SOURCES (source_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. 시험 회차
-- ---------------------------------------------------------------------
CREATE TABLE EXAM_ROUNDS (
  exam_round_id     BIGINT       NOT NULL AUTO_INCREMENT,
  certification_id  BIGINT       NOT NULL,
  source_id         BIGINT       NULL,
  source_exam_code  VARCHAR(80)  NULL,
  exam_year         INT          NULL,
  round_no          INT          NULL,
  exam_type         VARCHAR(30)  NULL,
  reg_start_at      DATETIME     NULL,
  reg_end_at        DATETIME     NULL,
  add_reg_start_at  DATETIME     NULL,
  add_reg_end_at    DATETIME     NULL,
  exam_date         DATE         NULL,
  exam_start_date   DATE         NULL,
  exam_end_date     DATE         NULL,
  result_date       DATE         NULL,
  last_synced_at    DATETIME     NULL,
  PRIMARY KEY (exam_round_id),
  CONSTRAINT fk_exam_rounds_cert   FOREIGN KEY (certification_id) REFERENCES CERTIFICATIONS (certification_id),
  CONSTRAINT fk_exam_rounds_source FOREIGN KEY (source_id)        REFERENCES DATA_SOURCES (source_id)
) ENGINE=InnoDB;

CREATE TABLE EXAM_SCHEDULE_CHANGE_LOGS (
  change_id            BIGINT        NOT NULL AUTO_INCREMENT,
  exam_round_id        BIGINT        NOT NULL,
  sync_log_id          BIGINT        NULL,
  old_exam_start_date  DATE          NULL,
  old_exam_end_date    DATE          NULL,
  new_exam_start_date  DATE          NULL,
  new_exam_end_date    DATE          NULL,
  old_schedule         JSON          NULL,
  new_schedule         JSON          NULL,
  changed_fields       JSON          NULL,
  change_reason        VARCHAR(500)  NULL,
  detected_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (change_id),
  CONSTRAINT fk_change_logs_round FOREIGN KEY (exam_round_id) REFERENCES EXAM_ROUNDS (exam_round_id),
  CONSTRAINT fk_change_logs_sync  FOREIGN KEY (sync_log_id)   REFERENCES DATA_SYNC_JOBS (sync_log_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. 참고 자료 (후기 · 통계)
-- ---------------------------------------------------------------------
CREATE TABLE STUDY_REFERENCE_STATS (
  stat_id           BIGINT        NOT NULL AUTO_INCREMENT,
  certification_id  BIGINT        NOT NULL,
  exam_type         VARCHAR(30)   NULL,
  mean_hours        DECIMAL(8,2)  NULL,
  min_hours         DECIMAL(8,2)  NULL,
  max_hours         DECIMAL(8,2)  NULL,
  sample_count      INT           NULL,
  base_date         DATE          NULL,
  PRIMARY KEY (stat_id),
  CONSTRAINT fk_ref_stats_cert FOREIGN KEY (certification_id) REFERENCES CERTIFICATIONS (certification_id)
) ENGINE=InnoDB;

CREATE TABLE PASS_REVIEWS (
  review_id         BIGINT        NOT NULL AUTO_INCREMENT,
  source_id         BIGINT        NULL,
  certification_id  BIGINT        NOT NULL,
  exam_type         VARCHAR(30)   NULL,
  major_type        VARCHAR(30)   NULL,
  source_url        VARCHAR(500)  NULL,
  posted_at         DATE          NULL,
  proof_yn          CHAR(1)       NULL,
  prep_days         INT           NULL,
  total_hours       DECIMAL(8,2)  NULL,
  daily_hours       VARCHAR(10)   NULL,
  study_subjects    VARCHAR(500)  NULL,
  evidence_text     TEXT          NULL,
  review_status     VARCHAR(30)   NULL,
  exclude_reason    VARCHAR(500)  NULL,
  PRIMARY KEY (review_id),
  CONSTRAINT fk_pass_reviews_source FOREIGN KEY (source_id)        REFERENCES DATA_SOURCES (source_id),
  CONSTRAINT fk_pass_reviews_cert   FOREIGN KEY (certification_id) REFERENCES CERTIFICATIONS (certification_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 5. 사용자 · 목표
-- ---------------------------------------------------------------------
CREATE TABLE USERS (
  user_id        BIGINT        NOT NULL AUTO_INCREMENT,
  email          VARCHAR(255)  NOT NULL,
  password_hash  VARCHAR(255)  NOT NULL,
  nickname       VARCHAR(50)   NULL,
  created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
  major_type     VARCHAR(50)   NULL,
  PRIMARY KEY (user_id),
  UNIQUE KEY uk_users_email (email)
) ENGINE=InnoDB;

CREATE TABLE USER_GOALS (
  goal_id               BIGINT        NOT NULL AUTO_INCREMENT,
  user_id               BIGINT        NOT NULL,
  certification_id      BIGINT        NOT NULL,
  target_exam_round_id  BIGINT        NULL,
  target_exam_date      DATE          NULL,
  goal_title            VARCHAR(200)  NULL,
  status                VARCHAR(30)   NULL,
  created_at            DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (goal_id),
  CONSTRAINT fk_user_goals_user  FOREIGN KEY (user_id)              REFERENCES USERS (user_id),
  CONSTRAINT fk_user_goals_cert  FOREIGN KEY (certification_id)     REFERENCES CERTIFICATIONS (certification_id),
  CONSTRAINT fk_user_goals_round FOREIGN KEY (target_exam_round_id) REFERENCES EXAM_ROUNDS (exam_round_id)
) ENGINE=InnoDB;

CREATE TABLE GOAL_SUBJECTS (
  goal_subject_id           BIGINT        NOT NULL AUTO_INCREMENT,
  goal_id                   BIGINT        NOT NULL,
  certification_subject_id  BIGINT        NOT NULL,
  familiarity_level         INT           NULL,
  priority                  INT           NULL,
  target_hours              DECIMAL(8,2)  NULL,
  progress_rate             DECIMAL(5,2)  NULL,
  PRIMARY KEY (goal_subject_id),
  CONSTRAINT fk_goal_subjects_goal    FOREIGN KEY (goal_id)                  REFERENCES USER_GOALS (goal_id),
  CONSTRAINT fk_goal_subjects_subject FOREIGN KEY (certification_subject_id) REFERENCES CERTIFICATION_SUBJECTS (certification_subject_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6. 학습 계획 · 기록
-- ---------------------------------------------------------------------
CREATE TABLE STUDY_PLANS (
  plan_id          BIGINT        NOT NULL AUTO_INCREMENT,
  user_id          BIGINT        NOT NULL,
  plan_name        VARCHAR(200)  NULL,
  plan_type        VARCHAR(30)   NULL,
  version_no       INT           NULL,
  start_date       DATE          NULL,
  end_date         DATE          NULL,
  weekday_minutes  JSON          NULL,
  status           VARCHAR(30)   NULL,
  PRIMARY KEY (plan_id),
  CONSTRAINT fk_study_plans_user FOREIGN KEY (user_id) REFERENCES USERS (user_id)
) ENGINE=InnoDB;

CREATE TABLE PLAN_GOALS (
  plan_id    BIGINT       NOT NULL,
  goal_id    BIGINT       NOT NULL,
  goal_role  VARCHAR(30)  NULL,
  priority   INT          NULL,
  PRIMARY KEY (plan_id, goal_id),
  CONSTRAINT fk_plan_goals_plan FOREIGN KEY (plan_id) REFERENCES STUDY_PLANS (plan_id),
  CONSTRAINT fk_plan_goals_goal FOREIGN KEY (goal_id) REFERENCES USER_GOALS (goal_id)
) ENGINE=InnoDB;

CREATE TABLE STUDY_PLAN_DETAILS (
  task_id                   BIGINT        NOT NULL AUTO_INCREMENT,
  user_id                   BIGINT        NOT NULL,
  plan_id                   BIGINT        NOT NULL,
  goal_id                   BIGINT        NULL,
  certification_subject_id  BIGINT        NULL,
  task_title                VARCHAR(200)  NULL,
  study_category            VARCHAR(50)   NULL,
  subject_name              VARCHAR(150)  NULL,
  scheduled_date            DATE          NULL,
  carried_from_date         DATE          NULL,
  estimated_minutes         INT           NULL,
  created_by                VARCHAR(30)   NULL,
  PRIMARY KEY (task_id),
  CONSTRAINT fk_plan_details_user    FOREIGN KEY (user_id)                  REFERENCES USERS (user_id),
  CONSTRAINT fk_plan_details_plan    FOREIGN KEY (plan_id)                  REFERENCES STUDY_PLANS (plan_id),
  CONSTRAINT fk_plan_details_goal    FOREIGN KEY (goal_id)                  REFERENCES USER_GOALS (goal_id),
  CONSTRAINT fk_plan_details_subject FOREIGN KEY (certification_subject_id) REFERENCES CERTIFICATION_SUBJECTS (certification_subject_id)
) ENGINE=InnoDB;

CREATE TABLE STUDY_SESSIONS (
  session_id       BIGINT       NOT NULL AUTO_INCREMENT,
  user_id          BIGINT       NOT NULL,
  task_id          BIGINT       NULL,
  study_date       DATE         NULL,
  start_time       TIME         NULL,
  end_time         TIME         NULL,
  actual_minutes   INT          NULL,
  input_method     VARCHAR(30)  NULL,
  digestion_level  INT          NULL,
  PRIMARY KEY (session_id),
  CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES USERS (user_id),
  CONSTRAINT fk_sessions_task FOREIGN KEY (task_id) REFERENCES STUDY_PLAN_DETAILS (task_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 7. AI · 챗봇
-- ---------------------------------------------------------------------
CREATE TABLE CHAT_CONVERSATIONS (
  con_id      BIGINT        NOT NULL AUTO_INCREMENT,
  user_id     BIGINT        NOT NULL,
  title       VARCHAR(200)  NULL,
  status      VARCHAR(30)   NULL,
  created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (con_id),
  CONSTRAINT fk_chat_conv_user FOREIGN KEY (user_id) REFERENCES USERS (user_id)
) ENGINE=InnoDB;

CREATE TABLE CHAT_MESSAGES (
  message_id  BIGINT       NOT NULL AUTO_INCREMENT,
  con_id      BIGINT       NOT NULL,
  role        VARCHAR(20)  NOT NULL,
  content     MEDIUMTEXT   NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (message_id),
  CONSTRAINT fk_chat_msg_conv FOREIGN KEY (con_id) REFERENCES CHAT_CONVERSATIONS (con_id)
) ENGINE=InnoDB;

CREATE TABLE AI_PLAN_PROPOSALS (
  proposal_id        BIGINT        NOT NULL AUTO_INCREMENT,
  user_id            BIGINT        NOT NULL,
  goal_id            BIGINT        NULL,
  current_plan_id    BIGINT        NULL,
  proposed_plan_id   BIGINT        NULL,
  message_id         BIGINT        NULL,
  delay_reason_type  VARCHAR(50)   NULL,
  delay_note         VARCHAR(500)  NULL,
  model_name         VARCHAR(100)  NULL,
  proposal_result    TEXT          NULL,
  acceptance_status  VARCHAR(30)   NULL,
  created_at         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  accepted_at        DATETIME      NULL,
  PRIMARY KEY (proposal_id),
  CONSTRAINT fk_proposals_user     FOREIGN KEY (user_id)          REFERENCES USERS (user_id),
  CONSTRAINT fk_proposals_goal     FOREIGN KEY (goal_id)          REFERENCES USER_GOALS (goal_id),
  CONSTRAINT fk_proposals_current  FOREIGN KEY (current_plan_id)  REFERENCES STUDY_PLANS (plan_id),
  CONSTRAINT fk_proposals_proposed FOREIGN KEY (proposed_plan_id) REFERENCES STUDY_PLANS (plan_id),
  CONSTRAINT fk_proposals_message  FOREIGN KEY (message_id)       REFERENCES CHAT_MESSAGES (message_id)
) ENGINE=InnoDB;

-- 확인: 20개가 나와야 함
SELECT COUNT(*) AS table_count FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'passpace_merged';
