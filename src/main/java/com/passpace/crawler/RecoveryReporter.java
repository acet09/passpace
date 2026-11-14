package com.passpace.crawler;

import com.passpace.constant.CollectSources;
import com.passpace.dto.collect.CollectDtos.RecoveryReport;
import com.passpace.crawler.ReviewUrlLedger.Entry;
import com.passpace.crawler.ReviewUrlLedger.Snapshot;
import com.passpace.repository.PassReviewRepository;
import com.passpace.repository.PassReviewRepository.CrawledRow;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * [용성] 복구율 리포트: 초기화 직전 기록(reset_snapshot.tsv) ↔ 지금 DB 를 주소 기준으로 비교한다.
 *  - 복구율: 초기화 전에 있던 글 중 지금 다시 저장된 비율 (전체 / VALID)
 *  - 값 일치율: 다시 저장된 글 중 합격 여부·시험 구분·전공·준비기간·하루시간·총시간·판정이 모두 같은 비율
 *  - 복구 못 한 글은 수집 이력의 마지막 결과로 이유를 보여 준다 (원글 삭제 404, 접근 거부 등)
 */
@Component
public class RecoveryReporter {

    static final List<Long> CRAWLED = List.of(CollectSources.VELOG_REVIEW, CollectSources.TISTORY_REVIEW);

    private final ReviewUrlLedger ledger;
    private final PassReviewRepository reviewRepository;

    public RecoveryReporter(ReviewUrlLedger ledger, PassReviewRepository reviewRepository) {
        this.ledger = ledger;
        this.reviewRepository = reviewRepository;
    }

    public RecoveryReport report() {
        Snapshot snap = ledger.readSnapshot();
        if (snap == null) {
            return new RecoveryReport(null, 0, 0, 0, 0, 0, 0, 0, 0, Map.of(), List.of(),
                    "초기화 직전 기록이 없습니다. '크롤링 후기 초기화'를 실행하면 그 직전 상태가 기록되고, 이후 복구율을 비교할 수 있습니다.");
        }
        Map<String, CrawledRow> now = reviewRepository.listBySources(CRAWLED).stream()
                .collect(Collectors.toMap(CrawledRow::url, Function.identity(), (a, b) -> a));
        int before = snap.rows().size(), beforeValid = 0, restored = 0, restoredValid = 0, same = 0;
        Map<String, int[]> bySite = new LinkedHashMap<>();
        List<String> missing = new ArrayList<>();
        for (CrawledRow b : snap.rows()) {
            String site = b.sourceId() == CollectSources.VELOG_REVIEW ? "VELOG" : "TISTORY";
            int[] c = bySite.computeIfAbsent(site, k -> new int[2]);
            c[0]++;
            boolean wasValid = "VALID".equals(b.status());
            if (wasValid) beforeValid++;
            CrawledRow a = now.get(b.url());
            if (a == null) {
                Entry e = ledger.get(b.url());
                if (missing.size() < 50) missing.add(b.url() + " (" + (e == null ? "이력 없음" : reason(e.lastResult())) + ")");
                continue;
            }
            restored++;
            c[1]++;
            if (wasValid && "VALID".equals(a.status())) restoredValid++;
            if (sameValues(b, a)) same++;
        }
        Map<String, String> sites = new LinkedHashMap<>();
        bySite.forEach((k, c) -> sites.put(k, c[1] + "/" + c[0] + " (" + pct(c[1], c[0]) + "%)"));
        String msg = "복구율 " + pct(restored, before) + "% (" + restored + "/" + before + ") · VALID "
                + pct(restoredValid, beforeValid) + "% (" + restoredValid + "/" + beforeValid + ") · 값 일치 "
                + pct(same, restored) + "% (" + same + "/" + restored + ")"
                + (missing.isEmpty() ? "" : " · 복구 못 한 글 " + (before - restored) + "건 (missing 목록 참고)");
        return new RecoveryReport(snap.takenAt(), before, beforeValid, restored, restoredValid,
                pct(restored, before), pct(restoredValid, beforeValid), same, pct(same, restored), sites, missing, msg);
    }

    /** 원문 없이 비교할 수 있는 구조화 값이 모두 같은지 */
    static boolean sameValues(CrawledRow b, CrawledRow a) {
        return Objects.equals(b.status(), a.status()) && Objects.equals(b.passYn(), a.passYn())
                && Objects.equals(b.examType(), a.examType()) && Objects.equals(b.majorType(), a.majorType())
                && Objects.equals(b.prepDays(), a.prepDays()) && Objects.equals(b.dailyMinutes(), a.dailyMinutes())
                && Objects.equals(b.totalHours(), a.totalHours()) && b.certificationId() == a.certificationId();
    }

    static String reason(String lastResult) {
        if (lastResult == null) return "미수집";
        return switch (lastResult) {
            case "FAIL:HTTP_404", "FAIL:HTTP_410" -> "원글 삭제";
            case "FAIL:LOGIN_REQUIRED" -> "비공개 전환";
            case "FAIL:ROBOTS_DENIED" -> "robots.txt 금지";
            case "FAIL:HTTP_403", "FAIL:HTTP_429", "FAIL:COOLDOWN" -> "사이트가 요청을 제한함 - 잠시 뒤 '복구 수집' 다시";
            case "FAIL:NETWORK" -> "응답 없음 - '실패분 다시 시도'";
            case "SKIP" -> "대상 자격증 아님으로 판정 바뀜";
            default -> lastResult.startsWith("SAVED") ? "아직 복구 수집 전" : lastResult;
        };
    }

    static double pct(int a, int b) {
        return b == 0 ? 0 : Math.round(a * 1000.0 / b) / 10.0;
    }
}
