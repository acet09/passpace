package com.passpace.service;

import com.passpace.dto.collect.CollectDtos.CollectJobStatus;
import com.passpace.dto.collect.CollectDtos.CollectResult;
import com.passpace.dto.collect.CollectDtos.DiscoverReport;
import com.passpace.dto.collect.CollectDtos.PreviewReport;
import com.passpace.dto.collect.CollectDtos.ResetReport;
import com.passpace.dto.collect.CollectDtos.ListingInspect;
import com.passpace.dto.collect.CertCountStatus;

/**
 * [용성] 합격·불합격 후기 수집
 *  목록·피드(사람이 고른 주소) → 후기 글 자동 탐색(1단계) → 크롤링 → 규칙 추출 → 정책 검사 → PASS_REVIEWS
 */
public interface ReviewCollectService {

    /** 탐색 + 수집 + 저장 (실행당 최대 review-max-per-run 건) */
    CollectResult collectReviews();

    /**
     * 백그라운드 수집 시작 (관리자 화면). 이미 실행 중이면 지금 상태를 그대로 돌려준다.
     * @param limit 새로 가져올 글 수 (10~1000으로 제한)
     * @param site  ALL / VELOG / TISTORY
     * @param tistorySearch true 면 티스토리 통합 검색 화면에서 새 블로그 글을 찾는다 (NEW 일 때만, PC 크롬 필요)
     * @param tistoryRss true 면 아는 티스토리 블로그의 RSS 로 새 글도 찾는다 (NEW 일 때만)
     * @param mode  NEW(탐색+직접 지정+수집 이력의 새 글) / RECOVER(수집 이력에서 저장했던 글만) / RETRY(마지막 실행의 일시 실패분)
     * 끝나면 참고 학습시간(STUDY_REFERENCE_STATS)을 자동으로 다시 집계한다.
     */
    CollectJobStatus startCollect(int limit, String site, String mode, boolean tistoryRss, boolean tistorySearch);

    default CollectJobStatus startCollect(int limit, String site, String mode) {
        return startCollect(limit, site, mode, false, false);
    }

    /** 일반 수집 (NEW) */
    default CollectJobStatus startCollect(int limit, String site) {
        return startCollect(limit, site, "NEW", false, false);
    }

    /** 백그라운드 수집 진행 상황 */
    CollectJobStatus jobStatus();

    /** 백그라운드 수집 중단 요청 (지금 처리 중인 글까지만 하고 멈춤) */
    CollectJobStatus cancelCollect();

    /** 목록·피드만 읽어 어떤 글이 후보로 잡히는지 확인 (글 페이지는 가져오지 않고 저장도 안 함) */
    DiscoverReport discover();

    /** 글 1개를 가져와 추출·검사 결과만 보여 준다 (저장 안 함) */
    PreviewReport preview(String url);

    /**
     * 크롤링 후기(velog·티스토리) 초기화.
     * execute=false 면 삭제 예정 건수만 보여 준다. 실행하면 서버 메모리의 "대상 아님" 기록도 비우고
     * 참고 학습시간을 다시 집계한다. 수집 중이면 실행하지 않는다.
     */
    ResetReport resetCrawledReviews(boolean execute);

    /** 목록 주소 1개를 열어 어떤 후기 글이 잡히는지 보여 준다 (글 페이지는 가져오지 않고 저장도 안 함) */
    ListingInspect inspectListing(String url);

    /** [11-14] 이번(또는 마지막) 크롤링 실행의 자격증별 건수. 구현이 없으면 빈 값 */
    default CertCountStatus certCountStatus() {
        return new CertCountStatus("CRAWL", "IDLE", java.util.Map.of());
    }
}
