-- 더미 후기만 지운다 (실제 수집 후기는 그대로)
USE passpace_merged;
DELETE FROM PASS_REVIEWS WHERE source_id = 4;
SELECT COUNT(*) AS remaining_reviews FROM PASS_REVIEWS;
