package com.passpace.controller;

import com.passpace.dto.collect.CollectDtos.CollectJobStatus;
import com.passpace.dto.collect.CollectDtos.CollectResult;
import com.passpace.dto.collect.CollectDtos.DiscoverReport;
import com.passpace.dto.collect.CollectDtos.PreviewReport;
import com.passpace.dto.collect.CollectDtos.ResetReport;
import com.passpace.dto.collect.CollectDtos.ListingInspect;
import com.passpace.dto.collect.CollectDtos.DbStatus;
import com.passpace.dto.collect.CollectDtos.RecoveryReport;
import com.passpace.crawler.RecoveryReporter;
import com.passpace.crawler.ReviewUrlLedger;
import com.passpace.crawler.SourceRegistry;
import com.passpace.repository.DbStatusChecker;
import java.util.LinkedHashMap;
import java.util.Map;
import com.passpace.service.ExamCollectService;
import com.passpace.service.ReviewCollectService;
import com.passpace.service.SqldScheduleCollectService;
import com.passpace.service.StudyReferenceAggregator;
import com.passpace.service.StudyReferenceAggregator.AggregateLine;

import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;
import com.passpace.util.ResponseUtil;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import com.passpace.service.NaverSearchReviewCollectService;
import com.passpace.service.DataqScheduleCollectService;
import org.springframework.beans.factory.annotation.Autowired;
import com.passpace.repository.JdbcCollectDataQuery;

/**
 * [용성] 관리자 수집 API  /admin/collect/**
 * ※ 화면(HTML)은 PageController 가 GET /admin/collect 로 돌려주고, 화면의 버튼이 아래 API 를 부른다.
 * ※ [JWT] 예전에는 관리자 비밀번호 + 세션(AdminAuthInterceptor)으로 잠갔다.
 *         이제는 SecurityConfig 의 .requestMatchers("/admin/**").hasRole("ADMIN") 한 줄이 막는다.
 *         → 토큰 없음 401, USER 토큰 403, ADMIN 토큰만 통과 (Controller 안에는 검사 코드가 없다)
 * ※ 응답은 모두 ResponseUtil.SUCCESS(...) → {"status":"SUCCESS","code":200,"data":...}
 * ※ 나중에 정기 수집은 @Scheduled 스케줄러가 같은 Service 를 호출하도록 확장한다.
 */
@RestController
public class CollectAdminController {

    private final ExamCollectService examCollectService;
    private final ReviewCollectService reviewCollectService;
    private final StudyReferenceAggregator referenceAggregator;
    private final SqldScheduleCollectService sqldScheduleCollectService;
    private final RecoveryReporter recoveryReporter;
    private final ReviewUrlLedger ledger;
    private final DbStatusChecker dbStatusChecker;
    private final SourceRegistry sourceRegistry;

    /** [11-14] 네이버 검색 API 영역 / 시험일정 2순위 수동 크롤링 (생성자는 그대로 두고 필드로 주입) */
    @Autowired
    private NaverSearchReviewCollectService naverCollectService;
    @Autowired
    private DataqScheduleCollectService dataqScheduleCollectService;
    /** [11-14] 수집 데이터 보기 (읽기 전용) */
    @Autowired
    private JdbcCollectDataQuery collectDataQuery;

    public CollectAdminController(ExamCollectService examCollectService, ReviewCollectService reviewCollectService,
                                  StudyReferenceAggregator referenceAggregator,
                                  SqldScheduleCollectService sqldScheduleCollectService,
                                  RecoveryReporter recoveryReporter, ReviewUrlLedger ledger,
                                  DbStatusChecker dbStatusChecker, SourceRegistry sourceRegistry) {
        this.examCollectService = examCollectService;
        this.reviewCollectService = reviewCollectService;
        this.referenceAggregator = referenceAggregator;
        this.sqldScheduleCollectService = sqldScheduleCollectService;
        this.recoveryReporter = recoveryReporter;
        this.ledger = ledger;
        this.dbStatusChecker = dbStatusChecker;
        this.sourceRegistry = sourceRegistry;
    }

    /** SQLD 시험일정 (2차 출처 크롤링) */
    @PostMapping("/admin/collect/sqld-schedule")
    public ResponseEntity<?> collectSqldSchedule() {
        return ResponseUtil.SUCCESS(sqldScheduleCollectService.collect());
    }


    /** 시험일정 수집 (공공데이터 API, 키가 없으면 샘플) */
    @PostMapping("/admin/collect/exam")
    public ResponseEntity<?> collectExam() {
        return ResponseUtil.SUCCESS(examCollectService.collectExamSchedule());
    }

    /** 후기 수집 (목록·피드 자동 탐색 + 직접 지정 URL). 끝나면 참고 학습시간을 다시 집계한다 */
    @PostMapping("/admin/collect/reviews")
    public ResponseEntity<?> collectReviews() {
        CollectResult result = reviewCollectService.collectReviews();
        referenceAggregator.refreshAll();
        return ResponseUtil.SUCCESS(result);
    }

    /** 백그라운드 수집 시작: 새로 가져올 글 수(10~1000)와 사이트(ALL/VELOG/TISTORY). 끝나면 참고 학습시간 자동 집계 */
    @PostMapping("/admin/collect/reviews/start")
    public ResponseEntity<?> startReviews(@RequestParam(value = "limit", defaultValue = "100") int limit,
                                         @RequestParam(value = "site", defaultValue = "ALL") String site,
                                         @RequestParam(value = "mode", defaultValue = "NEW") String mode,
                                         @RequestParam(value = "rss", defaultValue = "false") boolean rss,
                                         @RequestParam(value = "tsearch", defaultValue = "false") boolean tsearch) {
        return ResponseUtil.SUCCESS(reviewCollectService.startCollect(limit, site, mode, rss, tsearch));
    }

    // ---------------- 수집 범위(기준점) 관리 ----------------

    /** 지금 수집 범위: 목록 주소 전체 + 글 주소 수(목록은 앞 300개만) + 파일 위치 */
    @GetMapping("/admin/collect/sources")
    public ResponseEntity<?> sources() {
        Map<String, Object> m = new LinkedHashMap<>();
        var seeds = sourceRegistry.seeds();
        m.put("listings", sourceRegistry.listings());
        m.put("tistoryKeywords", sourceRegistry.tistoryKeywords().stream().map(k -> SourceRegistry.TISTORY_SEARCH + k).toList());
        m.put("naverKeywords", sourceRegistry.naverKeywords().stream().map(k -> SourceRegistry.NAVER_SEARCH + k).toList());
        m.put("seedCount", seeds.size());
        m.put("seeds", seeds);
        m.put("listingFile", sourceRegistry.listingPath().toString());
        m.put("seedFile", sourceRegistry.seedPath().toString());
        return ResponseUtil.SUCCESS(m);
    }

    /** velog 검색어 추가 */
    @PostMapping("/admin/collect/sources/velog-keyword")
    public ResponseEntity<?> addVelogKeyword(@RequestParam("keyword") String keyword) {
        return ResponseUtil.SUCCESS(sourceRegistry.addVelogKeyword(keyword));
    }

    /** 티스토리 검색어 추가 */
    @PostMapping("/admin/collect/sources/tistory-keyword")
    public ResponseEntity<?> addTistoryKeyword(@RequestParam("keyword") String keyword) {
        return ResponseUtil.SUCCESS(sourceRegistry.addTistoryKeyword(keyword));
    }

    /** [11-14] 네이버 검색 API 검색어 추가 (삭제는 /sources/remove 에 https://search.naver.com/search.naver?query=검색어) */
    @PostMapping("/admin/collect/sources/naver-keyword")
    public ResponseEntity<?> addNaverKeyword(@RequestParam("keyword") String keyword) {
        return ResponseUtil.SUCCESS(sourceRegistry.addNaverKeyword(keyword));
    }

    // ---------------- [11-14] 네이버 검색 API 영역 (블로그·카페 요약문 + 뉴스 참고) ----------------

    /** 네이버 수집 시작 (크롤링 실행 중이면 거절, 키가 없으면 "키 없음") */
    @PostMapping("/admin/collect/naver/start")
    public ResponseEntity<?> startNaver() {
        return ResponseUtil.SUCCESS(naverCollectService.start());
    }

    /** 네이버 수집 진행 상황 + 오늘 사용량 + 최근 뉴스(화면 참고용) */
    @GetMapping("/admin/collect/naver/status")
    public ResponseEntity<?> naverStatus() {
        return ResponseUtil.SUCCESS(naverCollectService.status());
    }

    /** 네이버 수집 중단 */
    @PostMapping("/admin/collect/naver/cancel")
    public ResponseEntity<?> cancelNaver() {
        return ResponseUtil.SUCCESS(naverCollectService.cancel());
    }

    /** [11-14] 이번(또는 마지막) 실행 기준 자격증별 건수: 크롤링 영역 / 네이버 영역 */
    @GetMapping("/admin/collect/status/by-cert")
    public ResponseEntity<?> statusByCert() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("crawl", reviewCollectService.certCountStatus());
        m.put("naver", naverCollectService.certCountStatus());
        return ResponseUtil.SUCCESS(m);
    }

    /** [11-14] 수집 데이터 요약: 출처별 · 자격증별 × 상태(VALID·PENDING·EXCLUDED) 건수 */
    @GetMapping("/admin/collect/data/summary")
    public ResponseEntity<?> dataSummary() {
        return ResponseUtil.SUCCESS(collectDataQuery.summary());
    }

    /** [11-14] 수집 후기 목록 (출처·자격증·상태·검색어 필터, 열 정렬, 한 쪽 10~200건) */
    @GetMapping("/admin/collect/data/reviews")
    public ResponseEntity<?> dataReviews(@RequestParam(value = "source", defaultValue = "ALL") String source,
                                         @RequestParam(value = "cert", defaultValue = "ALL") String cert,
                                         @RequestParam(value = "status", defaultValue = "ALL") String status,
                                         @RequestParam(value = "q", defaultValue = "") String keyword,
                                         @RequestParam(value = "sort", defaultValue = "id") String sort,
                                         @RequestParam(value = "dir", defaultValue = "desc") String dir,
                                         @RequestParam(value = "page", defaultValue = "0") int page,
                                         @RequestParam(value = "size", defaultValue = "50") int size) {
        return ResponseUtil.SUCCESS(collectDataQuery.reviews(source, cert, status, keyword, sort, dir, page, size));
    }

    /** [11-14] 시험일정 2순위: dataq 일정 페이지 크롤링 (관리자가 직접 실행, SQLD·ADsP) */
    @PostMapping("/admin/collect/manual/dataq-schedule")
    public ResponseEntity<?> collectDataqSchedule() {
        return ResponseUtil.SUCCESS(dataqScheduleCollectService.collect());
    }

    /** 주소 여러 줄 추가 (글 주소 / velog 태그·검색 화면 / 티스토리 RSS) */
    @PostMapping("/admin/collect/sources/urls")
    public ResponseEntity<?> addUrls(@RequestParam("text") String text) {
        return ResponseUtil.SUCCESS(sourceRegistry.addUrls(text));
    }

    /** 목록 주소 1개를 열어 찾은 후기 글 보기 (velog 검색어·태그, 티스토리 RSS) */
    @PostMapping("/admin/collect/sources/inspect")
    public ResponseEntity<?> inspectSource(@RequestParam("url") String url) {
        return ResponseUtil.SUCCESS(reviewCollectService.inspectListing(url));
    }

    /** 주소 1개 삭제 */
    @PostMapping("/admin/collect/sources/remove")
    public ResponseEntity<?> removeSource(@RequestParam("url") String url) {
        return ResponseUtil.SUCCESS(Map.of("removed", sourceRegistry.remove(url), "url", url));
    }

    /** 복구율 리포트: 초기화 직전 기록 ↔ 지금 DB (+ 수집 이력 파일 위치·건수) */
    @GetMapping("/admin/collect/reviews/recovery-report")
    public ResponseEntity<?> recoveryReport() {
        RecoveryReport r = recoveryReporter.report();
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("report", r);
        m.put("ledgerFile", ledger.ledgerPath().toString());
        m.put("ledgerUrls", ledger.size());
        m.put("ledgerEverSaved", ledger.everSaved().size());
        return ResponseUtil.SUCCESS(m);
    }

    /** DB 연결 성공/실패 + 테이블별 행 수 + 빈 테이블 */
    @GetMapping("/admin/collect/db-status")
    public ResponseEntity<?> dbStatus() {
        return ResponseUtil.SUCCESS(dbStatusChecker.check());
    }

    /** 백그라운드 수집 진행 상황 (화면이 3초마다 조회) */
    @GetMapping("/admin/collect/reviews/status")
    public ResponseEntity<?> reviewStatus() {
        return ResponseUtil.SUCCESS(reviewCollectService.jobStatus());
    }

    /** 백그라운드 수집 중단 (처리 중인 글까지만) */
    @PostMapping("/admin/collect/reviews/cancel")
    public ResponseEntity<?> cancelReviews() {
        return ResponseUtil.SUCCESS(reviewCollectService.cancelCollect());
    }

    /** 크롤링 후기 초기화 미리보기 (삭제 예정 건수만) */
    @GetMapping("/admin/collect/reviews/reset")
    public ResponseEntity<?> resetPreview() {
        return ResponseUtil.SUCCESS(reviewCollectService.resetCrawledReviews(false));
    }

    /** 크롤링 후기 초기화 실행: confirm 에 "초기화" 를 정확히 넣어야 실행 */
    @PostMapping("/admin/collect/reviews/reset")
    public ResponseEntity<?> reset(@RequestParam(value = "confirm", defaultValue = "") String confirm) {
        if (!"초기화".equals(confirm.strip())) {
            ResetReport preview = reviewCollectService.resetCrawledReviews(false);
            return ResponseUtil.SUCCESS(new ResetReport(false, preview.velog(), preview.tistory(), "확인 문구가 맞지 않아 삭제하지 않았습니다."));
        }
        return ResponseUtil.SUCCESS(reviewCollectService.resetCrawledReviews(true));
    }

    /** 탐색만: 목록·피드에서 어떤 글이 후보로 잡히는지 확인 (글 페이지는 가져오지 않고 저장 안 함) */
    @PostMapping("/admin/collect/reviews/discover")
    public ResponseEntity<?> discoverReviews() {
        return ResponseUtil.SUCCESS(reviewCollectService.discover());
    }

    /** 미리보기: 글 1개를 가져와 추출·검사 결과만 보여 준다 (저장 안 함) */
    @PostMapping("/admin/collect/reviews/preview")
    public ResponseEntity<?> previewReview(@RequestParam("url") String url) {
        return ResponseUtil.SUCCESS(reviewCollectService.preview(url));
    }

    /** 참고 학습시간(STUDY_REFERENCE_STATS) 다시 집계: 실측 표본 10건 이상이면 잠정값 대신 쓰인다 */
    @PostMapping("/admin/collect/reference-stats")
    public ResponseEntity<?> refreshReferenceStats() {
        return ResponseUtil.SUCCESS(referenceAggregator.refreshAll());
    }
}
