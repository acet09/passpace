package com.passpace.collect.repository;

/** [용성] DATA_SYNC_JOBS - 수집을 실행할 때마다 시작·종료·건수·오류를 남긴다 */
public interface SyncJobRepository {

    /** @return sync_log_id */
    long start(long sourceId, String syncTarget);

    void finish(long syncLogId, int success, int failed, int skipped, String status, String failType, String errorMessage);
}
