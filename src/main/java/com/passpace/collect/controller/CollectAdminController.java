package com.passpace.collect.controller;

import com.passpace.collect.dto.CollectDtos.CollectJobStatus;
import com.passpace.collect.dto.CollectDtos.CollectResult;
import com.passpace.collect.dto.CollectDtos.DiscoverReport;
import com.passpace.collect.dto.CollectDtos.PreviewReport;
import com.passpace.collect.dto.CollectDtos.ResetReport;
import com.passpace.collect.dto.CollectDtos.ListingInspect;
import com.passpace.collect.dto.CollectDtos.DbStatus;
import com.passpace.collect.dto.CollectDtos.RecoveryReport;
import com.passpace.collect.ledger.RecoveryReporter;
import com.passpace.collect.ledger.ReviewUrlLedger;
import com.passpace.collect.ledger.SourceRegistry;
import com.passpace.collect.repository.DbStatusChecker;
import java.util.LinkedHashMap;
import java.util.Map;
import com.passpace.collect.service.ExamCollectService;
import com.passpace.collect.service.ReviewCollectService;
import com.passpace.collect.service.SqldScheduleCollectService;
import com.passpace.collect.stats.StudyReferenceAggregator;
import com.passpace.collect.stats.StudyReferenceAggregator.AggregateLine;

import java.util.List;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

/**
 * [용성] 관리자 수집 실행 화면 /admin/collect
 * ※ /admin/** 는 관리자 비밀번호(passpace.admin.password)를 입력한 세션만 들어올 수 있다 (collect.web.AdminAuthInterceptor)
 * ※ 나중에 정기 수집은 @Scheduled 스케줄러가 같은 Service 를 호출하도록 확장한다.
 */
@Controller
public class CollectAdminController {

    private final ExamCollectService examCollectService;
    private final ReviewCollectService reviewCollectService;
    private final StudyReferenceAggregator referenceAggregator;
    private final SqldScheduleCollectService sqldScheduleCollectService;
    private final RecoveryReporter recoveryReporter;
    private final ReviewUrlLedger ledger;
    private final DbStatusChecker dbStatusChecker;
    private final SourceRegistry sourceRegistry;

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
    @ResponseBody
    public CollectResult collectSqldSchedule() {
        return sqldScheduleCollectService.collect();
    }

    @GetMapping("/admin/collect")
    public String page() {
        return "collect/admin";
    }

    /** 시험일정 수집 (공공데이터 API, 키가 없으면 샘플) */
    @PostMapping("/admin/collect/exam")
    @ResponseBody
    public CollectResult collectExam() {
        return examCollectService.collectExamSchedule();
    }

    /** 후기 수집 (목록·피드 자동 탐색 + 직접 지정 URL). 끝나면 참고 학습시간을 다시 집계한다 */
    @PostMapping("/admin/collect/reviews")
    @ResponseBody
    public CollectResult collectReviews() {
        CollectResult result = reviewCollectService.collectReviews();
        referenceAggregator.refreshAll();
        return result;
    }

    /** 백그라운드 수집 시작: 새로 가져올 글 수(10~1000)와 사이트(ALL/VELOG/TISTORY). 끝나면 참고 학습시간 자동 집계 */
    @PostMapping("/admin/collect/reviews/start")
    @ResponseBody
    public CollectJobStatus startReviews(@RequestParam(value = "limit", defaultValue = "100") int limit,
                                         @RequestParam(value = "site", defaultValue = "ALL") String site,
                                         @RequestParam(value = "mode", defaultValue = "NEW") String mode,
                                         @RequestParam(value = "rss", defaultValue = "false") boolean rss,
                                         @RequestParam(value = "tsearch", defaultValue = "false") boolean tsearch) {
        return reviewCollectService.startCollect(limit, site, mode, rss, tsearch);
    }

    // ---------------- 수집 범위(기준점) 관리 ----------------

    /** 지금 수집 범위: 목록 주소 전체 + 글 주소 수(목록은 앞 300개만) + 파일 위치 */
    @GetMapping("/admin/collect/sources")
    @ResponseBody
    public Map<String, Object> sources() {
        Map<String, Object> m = new LinkedHashMap<>();
        var seeds = sourceRegistry.seeds();
        m.put("listings", sourceRegistry.listings());
        m.put("tistoryKeywords", sourceRegistry.tistoryKeywords().stream().map(k -> SourceRegistry.TISTORY_SEARCH + k).toList());
        m.put("seedCount", seeds.size());
        m.put("seeds", seeds);
        m.put("listingFile", sourceRegistry.listingPath().toString());
        m.put("seedFile", sourceRegistry.seedPath().toString());
        return m;
    }

    /** velog 검색어 추가 */
    @PostMapping("/admin/collect/sources/velog-keyword")
    @ResponseBody
    public SourceRegistry.AddResult addVelogKeyword(@RequestParam("keyword") String keyword) {
        return sourceRegistry.addVelogKeyword(keyword);
    }

    /** 티스토리 검색어 추가 */
    @PostMapping("/admin/collect/sources/tistory-keyword")
    @ResponseBody
    public SourceRegistry.AddResult addTistoryKeyword(@RequestParam("keyword") String keyword) {
        return sourceRegistry.addTistoryKeyword(keyword);
    }

    /** 주소 여러 줄 추가 (글 주소 / velog 태그·검색 화면 / 티스토리 RSS) */
    @PostMapping("/admin/collect/sources/urls")
    @ResponseBody
    public SourceRegistry.AddResult addUrls(@RequestParam("text") String text) {
        return sourceRegistry.addUrls(text);
    }

    /** 목록 주소 1개를 열어 찾은 후기 글 보기 (velog 검색어·태그, 티스토리 RSS) */
    @PostMapping("/admin/collect/sources/inspect")
    @ResponseBody
    public ListingInspect inspectSource(@RequestParam("url") String url) {
        return reviewCollectService.inspectListing(url);
    }

    /** 주소 1개 삭제 */
    @PostMapping("/admin/collect/sources/remove")
    @ResponseBody
    public Map<String, Object> removeSource(@RequestParam("url") String url) {
        return Map.of("removed", sourceRegistry.remove(url), "url", url);
    }

    /** 복구율 리포트: 초기화 직전 기록 ↔ 지금 DB (+ 수집 이력 파일 위치·건수) */
    @GetMapping("/admin/collect/reviews/recovery-report")
    @ResponseBody
    public Map<String, Object> recoveryReport() {
        RecoveryReport r = recoveryReporter.report();
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("report", r);
        m.put("ledgerFile", ledger.ledgerPath().toString());
        m.put("ledgerUrls", ledger.size());
        m.put("ledgerEverSaved", ledger.everSaved().size());
        return m;
    }

    /** DB 연결 성공/실패 + 테이블별 행 수 + 빈 테이블 */
    @GetMapping("/admin/collect/db-status")
    @ResponseBody
    public DbStatus dbStatus() {
        return dbStatusChecker.check();
    }

    /** 백그라운드 수집 진행 상황 (화면이 3초마다 조회) */
    @GetMapping("/admin/collect/reviews/status")
    @ResponseBody
    public CollectJobStatus reviewStatus() {
        return reviewCollectService.jobStatus();
    }

    /** 백그라운드 수집 중단 (처리 중인 글까지만) */
    @PostMapping("/admin/collect/reviews/cancel")
    @ResponseBody
    public CollectJobStatus cancelReviews() {
        return reviewCollectService.cancelCollect();
    }

    /** 크롤링 후기 초기화 미리보기 (삭제 예정 건수만) */
    @GetMapping("/admin/collect/reviews/reset")
    @ResponseBody
    public ResetReport resetPreview() {
        return reviewCollectService.resetCrawledReviews(false);
    }

    /** 크롤링 후기 초기화 실행: confirm 에 "초기화" 를 정확히 넣어야 실행 */
    @PostMapping("/admin/collect/reviews/reset")
    @ResponseBody
    public ResetReport reset(@RequestParam(value = "confirm", defaultValue = "") String confirm) {
        if (!"초기화".equals(confirm.strip())) {
            ResetReport preview = reviewCollectService.resetCrawledReviews(false);
            return new ResetReport(false, preview.velog(), preview.tistory(), "확인 문구가 맞지 않아 삭제하지 않았습니다.");
        }
        return reviewCollectService.resetCrawledReviews(true);
    }

    /** 탐색만: 목록·피드에서 어떤 글이 후보로 잡히는지 확인 (글 페이지는 가져오지 않고 저장 안 함) */
    @PostMapping("/admin/collect/reviews/discover")
    @ResponseBody
    public DiscoverReport discoverReviews() {
        return reviewCollectService.discover();
    }

    /** 미리보기: 글 1개를 가져와 추출·검사 결과만 보여 준다 (저장 안 함) */
    @PostMapping("/admin/collect/reviews/preview")
    @ResponseBody
    public PreviewReport previewReview(@RequestParam("url") String url) {
        return reviewCollectService.preview(url);
    }

    /** 참고 학습시간(STUDY_REFERENCE_STATS) 다시 집계: 실측 표본 10건 이상이면 잠정값 대신 쓰인다 */
    @PostMapping("/admin/collect/reference-stats")
    @ResponseBody
    public List<AggregateLine> refreshReferenceStats() {
        return referenceAggregator.refreshAll();
    }
}
