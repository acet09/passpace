package com.passpace.collect;

import com.passpace.service.ReviewQualityChecker;
import com.passpace.service.RuleBasedReviewExtractor;
import com.passpace.constant.ExamType;
import com.passpace.constant.MajorType;
import com.passpace.constant.StudyMethod;
import com.passpace.domain.ExtractedReview;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** [용성] 규칙 추출기 테스트 - DB·Spring 없이 실행된다 */
class RuleBasedReviewExtractorTest {

    private final RuleBasedReviewExtractor extractor = new RuleBasedReviewExtractor();
    private final ReviewQualityChecker checker = new ReviewQualityChecker();

    @Test
    void 합격_후기에서_값을_뽑는다() {
        String text = "경영학과 비전공자입니다. 2025년 2회 정보처리기사 필기 최종 합격했습니다. "
                + "두 달 동안 하루 2시간 30분씩 공부했고 개념은 짧게 보고 기출만 반복했어요. 기출 5회독 했습니다. "
                + "데이터베이스 과목이 제일 어려웠습니다.";
        ExtractedReview r = extractor.extract("정처기 필기 합격 후기", text);

        assertThat(r.passed()).isTrue();
        assertThat(r.examType()).isEqualTo(ExamType.WRITTEN);
        assertThat(r.majorType()).isEqualTo(MajorType.NON_MAJOR);
        assertThat(r.examYear()).isEqualTo(2025);
        assertThat(r.roundNo()).isEqualTo(2);
        assertThat(r.prepDays()).isEqualTo(60);          // "두 달" → 준비 기간 60일 (총 공부시간 아님)
        assertThat(r.dailyMinutes()).isEqualTo(150);
        assertThat(r.totalHours()).isNull();             // 원문에 없으면 null
        assertThat(r.studyMethod()).isEqualTo(StudyMethod.PAST_EXAM);
        assertThat(r.proof()).isTrue();
        assertThat(r.evidenceText()).contains("하루 2시간 30분");
        assertThat(checker.check(r, text).reviewStatus()).isEqualTo("VALID");
    }

    @Test
    void 불합격과_이상값을_구분한다() {
        String text = "컴공 전공자. 3주 준비했는데 실기에서 떨어졌습니다. 하루 22시간 공부했어요.";
        ExtractedReview r = extractor.extract("실기 후기", text);

        assertThat(r.passed()).isFalse();
        assertThat(r.examType()).isEqualTo(ExamType.PRACTICAL);
        assertThat(r.majorType()).isEqualTo(MajorType.MAJOR);
        assertThat(r.prepDays()).isEqualTo(21);
        assertThat(checker.check(r, text).reviewStatus()).isEqualTo("EXCLUDED");   // 하루 20시간 이상
    }

    @Test
    void 시간_정보가_없거나_광고면_제외한다() {
        String noTime = "정처기 필기 합격했습니다! 다들 화이팅";
        assertThat(checker.check(extractor.extract("", noTime), noTime).excludeReason()).isEqualTo("시간 정보 없음");

        String ad = "하루 3시간 공부해서 합격. 이 강의는 협찬으로 제공받아 작성했습니다.";
        assertThat(checker.check(extractor.extract("", ad), ad).reviewStatus()).isEqualTo("EXCLUDED");
    }

    // ---------------- [11-19] 표·일지형 총 공부시간 ----------------

    @Test
    void 표_합계와_공부시간_문구에서_총시간을_분까지_뽑는다() {
        // hwankr 필기 후기 합계 행, kicdor 실기 후기 문구
        assertThat(extractor.extract("[정보처리기사] 필기 후기", "| **합계** | **23h 56m** | **7일** |").totalHours())
                .isEqualByComparingTo("23.93");
        assertThat(extractor.extract("정보처리기사 후기", "실기 시험 - 7.19 (토) 공부 시간 60시간 15분 공부 방법").totalHours())
                .isEqualByComparingTo("60.25");
        assertThat(extractor.extract("정처기 후기", "총 30시간 30분 공부했어요").totalHours()).isEqualByComparingTo("30.50");
    }

    @Test
    void 하루_단위_공부시간은_총시간이_아니다() {
        assertThat(extractor.extract("정처기 후기", "하루 공부 시간 3시간 정도였어요").totalHours()).isNull();
        assertThat(extractor.extract("정처기 후기", "평일엔 공부 시간 2시간씩 잡았어요").totalHours()).isNull();
        assertThat(extractor.extract("정처기 후기", "공부 시간의 30% 정도를 DB에 썼어요").totalHours()).isNull();
    }
}
