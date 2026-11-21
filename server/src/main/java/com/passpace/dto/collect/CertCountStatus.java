package com.passpace.dto.collect;

import java.util.Map;

/**
 * [용성·11-14] 이번 실행 기준 자격증별 수집 건수 (GET /admin/collect/status/by-cert).
 * 기존 CollectJobStatus 모양은 바꾸지 않고 따로 준다.
 *
 * @param area  CRAWL(크롤링 영역) / NAVER(네이버 검색 API 영역)
 * @param state IDLE / RUNNING / DONE / STOPPED / CANCELLED
 * @param byCert 자격증 코드(1320·SQLD·CA1·ADSP) → 건수
 */
public record CertCountStatus(String area, String state, Map<String, Row> byCert) {

    /**
     * @param saved        저장한 글 수 (VALID + PENDING + EXCLUDED)
     * @param unregistered CERTIFICATIONS 에 자격증 행이 없어 저장하지 않은 글 수 (db/09 실행 전)
     */
    public record Row(int saved, int valid, int pending, int excluded, int unregistered) {
    }

    /** "자격증코드|상태"(상태: VALID·PENDING·EXCLUDED·UNREGISTERED) → 건수 를 자격증별 Row 로 묶는다 */
    public static Map<String, Row> from(Map<String, ? extends Number> counts) {
        Map<String, int[]> acc = new java.util.TreeMap<>();
        counts.forEach((key, n) -> {
            String[] k = key.split("\\|", 2);
            if (k.length < 2) return;
            int[] a = acc.computeIfAbsent(k[0], x -> new int[4]);
            switch (k[1]) {
                case "VALID" -> a[0] += n.intValue();
                case "PENDING" -> a[1] += n.intValue();
                case "EXCLUDED" -> a[2] += n.intValue();
                case "UNREGISTERED" -> a[3] += n.intValue();
                default -> { }
            }
        });
        Map<String, Row> out = new java.util.LinkedHashMap<>();
        acc.forEach((code, a) -> out.put(code, new Row(a[0] + a[1] + a[2], a[0], a[1], a[2], a[3])));
        return out;
    }
}
