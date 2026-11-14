package com.passpace.service;

import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * [용성·11-14] 크롤링 영역과 네이버 검색 API 영역이 동시에 돌지 않게 하는 표시.
 * 네이버 영역이 실행 중이면 naverRunning=true → 크롤링 시작 요청은 "다른 수집 실행 중"으로 거절한다.
 * (반대 방향은 네이버 영역이 ReviewCollectService.jobStatus() 의 RUNNING 여부로 확인한다)
 */
@Component
public class CollectRunGuard {

    private final AtomicBoolean naverRunning = new AtomicBoolean(false);

    /** 네이버 영역 시작 표시. 이미 실행 중이면 false */
    public boolean beginNaver() {
        return naverRunning.compareAndSet(false, true);
    }

    public void endNaver() {
        naverRunning.set(false);
    }

    public boolean isNaverRunning() {
        return naverRunning.get();
    }
}
