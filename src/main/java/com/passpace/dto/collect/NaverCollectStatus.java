package com.passpace.dto.collect;

import com.passpace.dto.collect.CollectDtos.CollectJobStatus;

import java.util.List;

/**
 * [용성·11-14] 네이버 검색 API 영역 상태 (GET /admin/collect/naver/status)
 * 기존 CollectJobStatus 모양은 그대로 두고, 네이버 영역에만 있는 값(오늘 사용량·최근 뉴스)을 더해 감싼다.
 *
 * @param job        크롤링 영역과 같은 모양의 진행 상황 (bySite: NAVER_BLOG / NAVER_CAFE)
 * @param keyReady   네이버 검색 API 키가 설정되어 있는지
 * @param usedToday  오늘 호출 수 (서버 메모리, 재시작 시 0)
 * @param dailyLimit 설정 한도 (기본 20,000, 네이버 협의 한도 25,000)
 * @param recentNews 최근 뉴스 (3순위 참고 정보, DB 저장 안 함, 서버 메모리)
 */
public record NaverCollectStatus(CollectJobStatus job, boolean keyReady, int usedToday, int dailyLimit,
                                 List<NewsItem> recentNews) {

    /** 뉴스 1건: 제목·링크(원문 링크 우선)·날짜(yyyy-MM-dd) */
    public record NewsItem(String title, String link, String date) {
    }
}
