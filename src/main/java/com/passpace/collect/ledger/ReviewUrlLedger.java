package com.passpace.collect.ledger;

import com.passpace.collect.repository.PassReviewRepository.CrawledRow;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * [용성] 수집 이력 파일 (크롤링 데이터 복구용).
 *
 * 수집기가 한 번이라도 찾은 글 주소와 마지막 판정 결과를 프로젝트 폴더의 파일에 계속 쌓는다.
 *  - 저장: 시각 · 주소 · 사이트 · 결과(FOUND / SAVED:VALID / SAVED:EXCLUDED / SAVED:PENDING / SKIP / FAIL:종류)
 *  - 본문·작성자는 저장하지 않는다 (주소는 PASS_REVIEWS 에도 이미 저장하는 값)
 *  - DB 의 크롤링 후기가 지워져도 이 파일이 남아 있으므로 "한 번이라도 저장했던 글"을 다시 수집할 수 있다
 *    (velog 검색 화면은 최근 20개만 보여 주므로, 이 파일이 없으면 예전 글을 다시 찾을 수 없다)
 *  - 한 줄씩 덧붙이기만 한다 (파일을 다시 쓰지 않아 중간에 꺼져도 앞 기록이 깨지지 않음)
 *
 * 초기화 직전 상태(복구율 비교 기준)는 reset_snapshot.tsv 에 따로 남긴다.
 */
@Component
public class ReviewUrlLedger {

    private static final Logger log = LoggerFactory.getLogger(ReviewUrlLedger.class);
    private static final DateTimeFormatter TS = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    static final String LEDGER_FILE = "review_url_ledger.tsv";
    static final String SNAPSHOT_FILE = "reset_snapshot.tsv";

    /** 주소 1개의 누적 상태 */
    public record Entry(String url, String site, String firstSeen, String lastResult, String lastAt, boolean everSaved) {
    }

    /** 초기화 직전 기록 */
    public record Snapshot(String takenAt, List<CrawledRow> rows) {
    }

    private final Path dir;
    private final Path ledgerFile;
    private final Path snapshotFile;
    private final Map<String, Entry> entries = new LinkedHashMap<>();

    public ReviewUrlLedger(@Value("${passpace.collect.data-dir:collect-data}") String dataDir) {
        this.dir = Paths.get(dataDir).toAbsolutePath().normalize();
        this.ledgerFile = dir.resolve(LEDGER_FILE);
        this.snapshotFile = dir.resolve(SNAPSHOT_FILE);
        load();
    }

    private synchronized void load() {
        if (!Files.exists(ledgerFile)) {
            log.info("수집 이력 파일 없음 → 새로 만듭니다: {}", ledgerFile);
            return;
        }
        try {
            for (String line : Files.readAllLines(ledgerFile, StandardCharsets.UTF_8)) {
                if (line.isBlank() || line.startsWith("#")) continue;
                String[] f = line.split("\t", -1);
                if (f.length < 4) continue;
                apply(f[0], f[1], f[2], f[3]);
            }
            log.info("수집 이력 {}건 불러옴 ({})", entries.size(), ledgerFile);
        } catch (IOException e) {
            log.warn("수집 이력 파일을 읽지 못했습니다: {}", e.getMessage());
        }
    }

    private void apply(String at, String url, String site, String result) {
        Entry old = entries.get(url);
        boolean saved = result.startsWith("SAVED") || (old != null && old.everSaved());
        entries.put(url, new Entry(url, site, old == null ? at : old.firstSeen(), result, at, saved));
    }

    /** 탐색에서 찾은 주소 (처음 보는 주소만 기록) */
    public synchronized void found(String url, String site) {
        if (!entries.containsKey(url)) write(url, site, "FOUND");
    }

    /** 수집 결과 기록 */
    public synchronized void record(String url, String site, String result) {
        write(url, site, result);
    }

    private void write(String url, String site, String result) {
        String at = LocalDateTime.now().format(TS);
        apply(at, url, site, result);
        try {
            Files.createDirectories(dir);
            boolean fresh = !Files.exists(ledgerFile);
            String head = fresh ? "# 시각\t주소\t사이트\t결과 (PASS PACE 수집 이력, 본문 없음)\n" : "";
            Files.writeString(ledgerFile, head + at + "\t" + url + "\t" + site + "\t" + result + "\n",
                    StandardCharsets.UTF_8, StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        } catch (IOException e) {
            log.warn("수집 이력 기록 실패 ({}): {}", url, e.getMessage());
        }
    }

    /**
     * DB 에 이미 저장된 크롤링 후기를 이력에 맞춰 넣는다 (이력 파일이 생기기 전에 수집한 글 포함).
     * 이력에 "저장했음"으로 없는 주소만 기록하므로 여러 번 불러도 중복 기록되지 않는다.
     * @return 새로 기록한 수
     */
    public synchronized int importSaved(List<CrawledRow> rows) {
        int n = 0;
        for (CrawledRow r : rows) {
            Entry e = entries.get(r.url());
            if (e != null && e.everSaved()) continue;
            write(r.url(), r.sourceId() == com.passpace.collect.CollectSources.VELOG_REVIEW ? "VELOG" : "TISTORY", "SAVED:" + (r.status() == null ? "UNKNOWN" : r.status()));
            n++;
        }
        return n;
    }

    /** 한 번이라도 DB 에 저장했던 주소 (복구 수집 대상) */
    public synchronized List<Entry> everSaved() {
        return entries.values().stream().filter(Entry::everSaved).toList();
    }

    public synchronized Entry get(String url) {
        return entries.get(url);
    }

    public synchronized int size() {
        return entries.size();
    }

    public Path ledgerPath() {
        return ledgerFile;
    }

    // ---------------- 초기화 직전 기록 ----------------

    /** 초기화 직전 상태 저장 (지울 후기가 없으면 이전 기록을 덮어쓰지 않는다) */
    public synchronized void writeSnapshot(List<CrawledRow> rows) {
        if (rows.isEmpty()) return;
        StringBuilder sb = new StringBuilder("# taken\t" + LocalDateTime.now().format(TS) + "\n");
        for (CrawledRow r : rows) {
            sb.append(String.join("\t", r.url(), String.valueOf(r.sourceId()), String.valueOf(r.certificationId()),
                    n(r.status()), n(r.passYn()), n(r.examType()), n(r.majorType()), n(r.prepDays()),
                    n(r.dailyMinutes()), n(r.totalHours()))).append('\n');
        }
        try {
            Files.createDirectories(dir);
            Files.writeString(snapshotFile, sb.toString(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("초기화 직전 기록을 남기지 못했습니다: " + snapshotFile, e);
        }
    }

    public synchronized Snapshot readSnapshot() {
        if (!Files.exists(snapshotFile)) return null;
        try {
            List<String> lines = Files.readAllLines(snapshotFile, StandardCharsets.UTF_8);
            String taken = null;
            List<CrawledRow> rows = new ArrayList<>();
            for (String line : lines) {
                if (line.startsWith("# taken\t")) {
                    taken = line.substring(8);
                    continue;
                }
                String[] f = line.split("\t", -1);
                if (f.length < 10) continue;
                rows.add(new CrawledRow(f[0], Long.parseLong(f[1]), Long.parseLong(f[2]), v(f[3]), v(f[4]), v(f[5]),
                        v(f[6]), i(f[7]), i(f[8]), v(f[9])));
            }
            return new Snapshot(taken, rows);
        } catch (IOException | RuntimeException e) {
            log.warn("초기화 직전 기록을 읽지 못했습니다: {}", e.getMessage());
            return null;
        }
    }

    private static String n(Object o) {
        return o == null ? "" : o.toString();
    }

    private static String v(String s) {
        return s == null || s.isEmpty() ? null : s;
    }

    private static Integer i(String s) {
        return s == null || s.isEmpty() ? null : Integer.valueOf(s);
    }
}
