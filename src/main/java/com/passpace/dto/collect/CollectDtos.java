package com.passpace.dto.collect;

import com.passpace.constant.ExamType;
import com.passpace.domain.ExtractedReview;

import java.time.LocalDate;
import java.util.List;

/** [용성] 수집 과정에서 주고받는 값들 (record 모음) */
public final class CollectDtos {

    private CollectDtos() {
    }

    /**
     * 시험일정 API 한 줄을 필기/실기로 나눈 값.
     * API 는 날짜(yyyyMMdd)만 주므로 접수 시각은 00:00 으로 저장한다.
     */
    public record ExamScheduleItem(int examYear, int roundNo, ExamType examType,
                                   LocalDate regStart, LocalDate regEnd,
                                   LocalDate examStart, LocalDate examEnd, LocalDate resultDate,
                                   String description) {
    }

    /**
     * 크롤링한 글 페이지 (본문 text 는 메모리에서만 사용하고 버린다)
     * @param postedAt   작성일 (못 찾으면 null → 3년 이내 확인 불가로 제외)
     * @param authorHash 작성자 해시 (아이디 원본은 담지 않는다)
     * @param noReprint  "무단 전재 금지" 류 표시 여부
     */
    public record FetchedPage(String url, String title, String text, LocalDate postedAt,
                              String authorHash, boolean noReprint) {
    }

    /** 수집 실행 결과 → 관리자 화면에 JSON 으로 표시 */
    public record CollectResult(String target, String mode, int success, int failed, int skipped,
                                String status, String message) {
    }

    /** 후기 품질 검사 결과 */
    public record QualityResult(String reviewStatus, String excludeReason) {
    }

    /** 탐색만 해 본 결과 (글 페이지는 가져오지 않음) */
    public record DiscoverReport(List<String> messages, List<CandidateView> candidates) {
    }

    /** 탐색으로 찾은 후기 후보 1개 */
    public record CandidateView(String url, String site, String label, LocalDate listedDate, boolean alreadySaved) {
    }

    /**
     * 글 1개를 저장하지 않고 분석해 본 결과 (관리자 화면 미리보기)
     * @param verdict SAVE_VALID / SAVE_EXCLUDED / SAVE_PENDING / SKIP(저장 대상 아님)
     */
    public record PreviewReport(String url, String site, String verdict, String certificateCode,
                                LocalDate postedAt, boolean authorHashed, ExtractedReview review,
                                QualityResult quality, String message) {
    }

    /**
     * 백그라운드 후기 수집 진행 상황 (관리자 화면이 몇 초마다 조회)
     * @param state     IDLE(실행한 적 없음) / RUNNING / DONE / STOPPED(403·429 중단) / CANCELLED(관리자 중단)
     * @param target    이번 실행 목표 건수 (새로 가져올 글 수)
     * @param processed 지금까지 처리한 글 수 (저장·건너뜀·실패 모두 포함)
     * @param saved     저장한 글 수 (VALID·EXCLUDED·PENDING)
     * @param valid     그중 통계에 쓰이는 VALID 수
     * @param oldSkipped 목록 작성일이 3년보다 오래돼 가져오지 않은 수
     * @param candidates 실행 시작 때 새로 가져올 수 있던 후보 수 (목표보다 적으면 후보 부족)
     * @param mode      NEW / RECOVER(복구 수집) / RETRY(실패분 다시 시도)
     * @param retryable 이번 실행에서 일시적으로 실패해 다시 시도할 수 있는 글 수
     * @param phase     지금 하는 일 (목록 읽는 중 n/m · RSS 읽는 중 · 글 수집 중), 끝나면 null
     */
    public record CollectJobStatus(String state, String site, int target, int candidates, int processed,
                                   int saved, int valid, int skipped, int failed, int oldSkipped,
                                   java.util.Map<String, String> bySite, String startedAt, long elapsedSeconds,
                                   String message, String mode, int retryable, String phase) {
    }

    /**
     * 크롤링 후기 초기화 결과 (velog·티스토리 출처만, 더미·시험일정·회원 데이터는 대상 아님)
     * @param executed false 면 미리보기(삭제 안 함)
     */
    public record ResetReport(boolean executed, int velog, int tistory, String message) {
    }

    /** 복구율 리포트 (초기화 직전 기록 ↔ 지금 DB) */
    public record RecoveryReport(String snapshotAt, int before, int beforeValid, int restored, int restoredValid,
                                 double restoreRate, double validRestoreRate, int sameValues, double sameValueRate,
                                 java.util.Map<String, String> bySite, List<String> missing, String message) {
    }

    /** DB 연결·테이블 상태 */
    public record DbStatus(boolean connected, String database, String version, long elapsedMs, String error,
                           int tableCount, List<TableCount> tables, List<String> emptyTables) {
    }

    public record TableCount(String table, long rows) {
    }

    /** 목록 주소 1개(velog 검색어·태그, 티스토리 RSS)를 열어 본 결과: 찾은 후기 글 (저장 안 함) */
    public record ListingInspect(String url, int linkCount, List<CandidateView> candidates, String message) {
    }
}
