-- [용성·3차] 이미 만들어 둔 passpace_merged DB 를 지우지 않고 후기 수집기 변경만 반영한다.
-- (DB 를 처음부터 만들 때는 01 → 02 → 03 만 실행하면 되고, 이 파일은 필요 없다)
-- 여러 번 실행해도 안전하다.
USE passpace_merged;

ALTER TABLE `PASS_REVIEWS`
  ADD COLUMN IF NOT EXISTS `author_hash` CHAR(64) NULL COMMENT '작성자 해시 SHA-256 (아이디 원본 저장 안 함, 같은 작성자 1표본) (확장)',
  ADD INDEX IF NOT EXISTS `IX_PASS_REVIEWS_AUTHOR` (`author_hash`);

-- velog: 2026-11-03 robots·약관 확인 완료
UPDATE DATA_SOURCES SET permission_checked_at = '2026-11-03 00:00:00'
 WHERE source_id = 3 AND permission_checked_at IS NULL;

-- 티스토리: 확인 전이므로 permission_checked_at 은 NULL (수집 프로그램이 건너뜀)
INSERT IGNORE INTO DATA_SOURCES (source_id, source_name, source_type, provider_name, base_url, active_yn, created_at, permission_checked_at)
VALUES (7, '티스토리 합격·불합격 후기', 'CRAWL', 'tistory', 'https://www.tistory.com', 'Y', NOW(), NULL);

-- SQLD 시험일정: 공공데이터 API (15062838)
INSERT IGNORE INTO DATA_SOURCES (source_id, source_name, source_type, provider_name, base_url, active_yn, created_at, permission_checked_at)
VALUES (8, '데이터 자격검정 시험 정보 API(15062838)', 'API', '한국데이터산업진흥원', 'https://api.odcloud.kr/api/15062838/v1', 'Y', NOW(), NULL);

SELECT source_id, provider_name, permission_checked_at FROM DATA_SOURCES WHERE source_id IN (3, 7, 8);
