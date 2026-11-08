package com.passpace.collect.client;

/**
 * [용성] 수집 실패. failType 은 DATA_SYNC_JOBS.fail_type 에 그대로 기록된다.
 * 예) API_RESULT_99(큐넷 일시 오류), HTTP_403(키 반영 대기·차단), HTTP_429(요청 과다), ROBOTS_DENIED
 */
public class CollectException extends RuntimeException {

    private final String failType;

    public CollectException(String failType, String message) {
        super(message);
        this.failType = failType;
    }

    public String getFailType() {
        return failType;
    }
}
