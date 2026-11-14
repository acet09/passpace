package com.passpace.service;

import com.passpace.constant.ExamType;
import com.passpace.crawler.AuthorHasher;
import com.passpace.domain.ExtractedReview;
import com.passpace.dto.collect.CollectDtos.QualityResult;
import com.passpace.repository.ExamRoundRepository;
import com.passpace.repository.PassReviewRepository;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * [용성·11-14] 요약문 출처(네이버 블로그·카페) 후기 1건 저장: 판별 → 추출 → 요약문 검사 → PASS_REVIEWS.
 *
 * 이미 나뉘어 있는 CertificateDetector · ReviewExtractor · ReviewQualityChecker · PassReviewRepository 를
 * 불러 쓰기만 한다. 크롤링 영역(ReviewCollectServiceImpl)은 지금처럼 자기 코드로 처리하고 이 클래스를 쓰지 않는다.
 *  - source_id 는 NULL (DATA_SOURCES 행을 추가하지 않음, 사이트 구분은 source_url 주소)
 *  - 요약문 출처는 VALID 로 저장하지 않는다 (ReviewQualityChecker.checkSnippet)
 *  - CERTIFICATIONS 에 자격증 행이 없으면(db/09 실행 전) 저장하지 않고 UNREGISTERED 로 돌려준다
 */
@Service
public class ReviewIngestService {

    /** 처리 결과: SAVED_VALID·SAVED_PENDING·SAVED_EXCLUDED / DUPLICATE / NOT_TARGET / UNREGISTERED */
    public record Outcome(String result, String certCode, String reviewStatus, String reason) {
        public boolean saved() {
            return result.startsWith("SAVED");
        }
    }

    private final ReviewExtractor extractor;
    private final ReviewQualityChecker qualityChecker;
    private final PassReviewRepository reviewRepository;
    private final ExamRoundRepository examRoundRepository;
    private final AuthorHasher authorHasher;
    /** 자격증 코드 → certification_id (행이 있을 때만 저장해 두고, 없으면 다음에 다시 찾는다) */
    private final Map<String, Long> certIds = new ConcurrentHashMap<>();

    public ReviewIngestService(ReviewExtractor extractor, ReviewQualityChecker qualityChecker,
                               PassReviewRepository reviewRepository, ExamRoundRepository examRoundRepository,
                               AuthorHasher authorHasher) {
        this.extractor = extractor;
        this.qualityChecker = qualityChecker;
        this.reviewRepository = reviewRepository;
        this.examRoundRepository = examRoundRepository;
        this.authorHasher = authorHasher;
    }

    /**
     * @param siteName  작성자 해시용 출처 이름 (NAVER_BLOG / NAVER_CAFE)
     * @param authorKey 작성자 구분값 원본 (저장하지 않음, 없으면 null)
     */
    public Outcome ingestSnippet(String url, String title, String snippet, LocalDate postedAt,
                                 String siteName, String authorKey) {
        if (reviewRepository.existsByUrl(url)) return new Outcome("DUPLICATE", null, null, "이미 저장한 주소");
        Optional<String> code = CertificateDetector.detect(title, snippet);
        if (code.isEmpty()) return new Outcome("NOT_TARGET", null, null, "대상 자격증 판단 불가 또는 둘 이상 언급");
        Long certId = certId(code.get());
        if (certId == null) {
            return new Outcome("UNREGISTERED", code.get(), null, "CERTIFICATIONS 에 " + code.get() + " 없음 (db/09 실행 필요)");
        }

        ExtractedReview review = extractor.extract(title, snippet);
        if (("SQLD".equals(code.get()) || "ADSP".equals(code.get())) && review.examType() != ExamType.WRITTEN) {
            review = RuleBasedReviewExtractor.withExamType(review, ExamType.WRITTEN);
        }
        String text = (title == null ? "" : title) + " " + (snippet == null ? "" : snippet);
        QualityResult quality = qualityChecker.checkSnippet(review, text, postedAt);
        reviewRepository.insertWithNullableSource(null, certId, url, postedAt,
                authorHasher.hashFor(siteName, authorKey), review, quality);
        return new Outcome("SAVED_" + quality.reviewStatus(), code.get(), quality.reviewStatus(), quality.excludeReason());
    }

    private Long certId(String code) {
        Long id = certIds.get(code);
        if (id != null) return id;
        Optional<Long> found = examRoundRepository.findCertificationId(code);
        found.ifPresent(v -> certIds.put(code, v));
        return found.orElse(null);
    }
}
