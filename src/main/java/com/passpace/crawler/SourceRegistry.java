package com.passpace.crawler;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

/**
 * [용성] 수집 범위(기준점) 관리 — 관리자 화면에서 고칠 수 있도록 프로젝트 폴더 파일로 관리한다.
 *
 *  - review_discovery_sources.txt : 목록 주소 (velog 태그·검색 화면, 티스토리 블로그 RSS) → 수집기가 열어서 글을 찾음
 *  - review_seed_urls.txt         : 글 주소 (주로 티스토리) → 그 글 하나를 수집
 *
 * 처음 실행할 때 프로그램 안의 기본 파일(src/main/resources/collect/)을 data-dir 로 복사하고,
 * 기본 velog 검색어를 더한다. 이후에는 data-dir 의 파일만 읽고 쓰며, 서버 재시작 없이 다음 수집부터 반영된다.
 */
@Component
public class SourceRegistry {

    private static final Logger log = LoggerFactory.getLogger(SourceRegistry.class);
    static final String LISTING_FILE = "review_discovery_sources.txt";
    static final String SEED_FILE = "review_seed_urls.txt";
    static final String VELOG_SEARCH = "https://velog.io/search?q=";
    static final String TISTORY_KEYWORD_FILE = "tistory_search_keywords.txt";
    /** 화면·API 에서 티스토리 검색어를 주소 모양으로 다루기 위한 앞부분 (파일에는 검색어만 저장) */
    public static final String TISTORY_SEARCH = "https://www.tistory.com/search?keyword=";

    /** 기본 티스토리 검색어. 하루 공부시간이 자세한 글(직장인·계획·공부시간)을 노리는 검색어 포함 */
    static final List<String> DEFAULT_TISTORY_KEYWORDS = List.of(
            "정처기 실기 합격 후기", "정처기 필기 합격 후기", "정보처리기사 실기 합격", "정보처리기사 필기 합격",
            "정처기 비전공 합격", "정처기 독학 합격", "정처기 직장인 합격", "정처기 하루 공부시간", "정처기 공부 계획",
            "정처기 벼락치기 합격", "정처기 실기 독학", "정처기 필기 일주일", "2026 정처기 실기", "2025 정처기 실기",
            "SQLD 합격 후기", "SQLD 독학 합격", "SQLD 벼락치기",
            // [11-14] 컴활 1급·ADsP
            "컴활 1급 합격 후기", "컴활 1급 필기 합격", "컴활 1급 실기 합격", "컴퓨터활용능력 1급 독학",
            "ADsP 합격 후기", "ADsP 독학 합격", "ADsP 비전공 합격");

    /** 기본 velog 검색어 (검색어 1개 = 최근 글 약 20개). 연도·회차·필기/실기·전공·공부 방식 조합 */
    static final List<String> DEFAULT_VELOG_KEYWORDS = List.of(
            "정보처리기사 합격", "정보처리기사 필기 후기", "정보처리기사 실기 후기", "정보처리기사 공부 기록", "정보처리기사 취득",
            "정처기 필기 후기", "정처기 실기 후기", "정처기 비전공", "정처기 비전공자 합격", "정처기 독학",
            "정처기 벼락치기", "정처기 2주", "정처기 한달", "정처기 공부법", "정처기 회고", "정처기 합격 회고",
            "정처기 불합격", "정처기 재수", "정처기 취득", "정처기 1회", "정처기 2회", "정처기 3회",
            "정처기 2024", "정처기 2025", "정처기 2026", "2025 정보처리기사", "2026 정보처리기사",
            "SQLD 합격", "SQLD 독학", "SQLD 공부법", "SQLD 비전공", "SQLD 회고", "SQLD 취득",
            "SQLD 벼락치기", "SQLD 2025", "SQLD 2026", "SQL 개발자 후기",
            // [11-14] 컴활 1급·ADsP
            "컴활 1급 합격", "컴활 1급 실기 후기", "컴활 1급 필기 후기", "컴퓨터활용능력 1급",
            "ADsP 합격", "ADsP 후기", "ADsP 독학", "ADsP 2026", "데이터분석 준전문가");

    /** [11-14] 이번에 새로 넣은 기본 검색어 (이미 파일이 있는 PC 에도 서버 시작 시 한 번만 추가) */
    static final List<String> NEW_VELOG_KEYWORDS_2026_11 = List.of(
            "컴활 1급 합격", "컴활 1급 실기 후기", "컴활 1급 필기 후기", "컴퓨터활용능력 1급",
            "ADsP 합격", "ADsP 후기", "ADsP 독학", "ADsP 2026", "데이터분석 준전문가");
    static final List<String> NEW_TISTORY_KEYWORDS_2026_11 = List.of(
            "컴활 1급 합격 후기", "컴활 1급 필기 합격", "컴활 1급 실기 합격", "컴퓨터활용능력 1급 독학",
            "ADsP 합격 후기", "ADsP 독학 합격", "ADsP 비전공 합격");
    /** [11-14] 디시인사이드 정보처리 미니갤 목록 (기본 목록 주소) */
    static final String DCINSIDE_DEFAULT_LISTING = "https://gall.dcinside.com/mini/board/lists/?id=dataprocessing";
    /** 한 번 적용 표시 파일: 있으면 위 새 기본값을 다시 넣지 않는다 (관리자가 지운 검색어가 되살아나지 않게) */
    static final String DEFAULTS_DONE_FILE = ".defaults-2026-11.done";

    // ---------------- [11-14] 네이버 검색 API 검색어 ----------------
    static final String NAVER_KEYWORD_FILE = "naver_keywords.txt";
    /** 화면·API 에서 네이버 검색어를 주소 모양으로 다루기 위한 앞부분 (파일에는 검색어만 저장, 삭제 API 공용) */
    public static final String NAVER_SEARCH = "https://search.naver.com/search.naver?query=";

    /** 주소 추가 결과 */
    public record AddResult(int addedListings, int addedSeeds, int duplicates, List<String> invalid, String message) {
    }

    private final Path listingFile;
    private final Path seedFile;
    private final Path tistoryKeywordFile;
    private Path naverKeywordFile;
    private final Set<String> naverKeywords = new LinkedHashSet<>();
    private final List<String> naverKeywordHeader = new ArrayList<>();
    private final Set<String> tistoryKeywords = new LinkedHashSet<>();
    private final List<String> tistoryKeywordHeader = new ArrayList<>();
    private final Set<String> listings = new LinkedHashSet<>();
    private final Set<String> seeds = new LinkedHashSet<>();
    private final List<String> listingHeader = new ArrayList<>();
    private final List<String> seedHeader = new ArrayList<>();

    public SourceRegistry(@Value("${passpace.collect.data-dir:collect-data}") String dataDir) {
        Path dir = Paths.get(dataDir).toAbsolutePath().normalize();
        this.listingFile = dir.resolve(LISTING_FILE);
        this.seedFile = dir.resolve(SEED_FILE);
        this.tistoryKeywordFile = dir.resolve(TISTORY_KEYWORD_FILE);
        init(dir);
    }

    private synchronized void init(Path dir) {
        try {
            Files.createDirectories(dir);
            boolean firstListing = !Files.exists(listingFile);
            if (firstListing) copyDefault("collect/" + LISTING_FILE, listingFile);
            if (!Files.exists(seedFile)) copyDefault("collect/" + SEED_FILE, seedFile);
            if (!Files.exists(tistoryKeywordFile)) {
                Files.writeString(tistoryKeywordFile, "# 티스토리 검색어 (한 줄에 하나, 관리자 화면에서 추가·삭제)\n"
                        + String.join("\n", DEFAULT_TISTORY_KEYWORDS) + "\n", StandardCharsets.UTF_8);
            }
            read(tistoryKeywordFile, tistoryKeywordHeader, tistoryKeywords);
            read(listingFile, listingHeader, listings);
            read(seedFile, seedHeader, seeds);
            if (firstListing) {
                for (String k : DEFAULT_VELOG_KEYWORDS) listings.add(VELOG_SEARCH + k);
                listings.add(DCINSIDE_DEFAULT_LISTING);
                save(listingFile, listingHeader, listings);
            }
            applyNewDefaultsOnce(dir, firstListing);
            initNaverKeywords(dir);
            log.info("수집 범위: 목록 {}개, 글 주소 {}개 ({})", listings.size(), seeds.size(), dir);
        } catch (IOException e) {
            log.warn("수집 범위 파일을 준비하지 못했습니다: {}", e.getMessage());
        }
    }

    /**
     * [11-14] 이미 collect-data 파일이 있는 PC 에도 이번에 새로 넣은 기본값(컴활·ADsP 검색어, 디시 목록)을
     * 파일에 없는 것만 한 번 추가한다. 추가 후 표시 파일을 만들어 다음 실행부터는 다시 넣지 않는다.
     */
    private void applyNewDefaultsOnce(Path dir, boolean firstListing) throws IOException {
        Path done = dir.resolve(DEFAULTS_DONE_FILE);
        if (Files.exists(done)) return;
        if (!firstListing) {
            boolean changed = false;
            for (String k : NEW_VELOG_KEYWORDS_2026_11) changed |= listings.add(VELOG_SEARCH + k);
            changed |= listings.add(DCINSIDE_DEFAULT_LISTING);
            if (changed) save(listingFile, listingHeader, listings);
            boolean changedT = false;
            for (String k : NEW_TISTORY_KEYWORDS_2026_11) changedT |= tistoryKeywords.add(k);
            if (changedT) save(tistoryKeywordFile, tistoryKeywordHeader, tistoryKeywords);
        }
        Files.writeString(done, "# 2026-11 기본 검색어(컴활·ADsP)·디시 목록을 한 번 추가함. 지우면 서버 시작 시 다시 추가\n",
                StandardCharsets.UTF_8);
    }

    /** [11-14] 네이버 검색어: 처음 실행 시 resources/collect/naver_keywords.txt 를 data-dir 로 복사 */
    private void initNaverKeywords(Path dir) throws IOException {
        naverKeywordFile = dir.resolve(NAVER_KEYWORD_FILE);
        if (!Files.exists(naverKeywordFile)) copyDefault("collect/" + NAVER_KEYWORD_FILE, naverKeywordFile);
        read(naverKeywordFile, naverKeywordHeader, naverKeywords);
    }

    public synchronized List<String> naverKeywords() {
        return List.copyOf(naverKeywords);
    }

    /** [11-14] 네이버 검색어 1개 추가 (티스토리 검색어 추가와 같은 모양) */
    public synchronized AddResult addNaverKeyword(String keyword) {
        String k = keyword == null ? "" : keyword.strip().replaceAll("\\s+", " ");
        if (k.isEmpty() || k.length() > 50 || k.startsWith("http")) {
            return new AddResult(0, 0, 0, List.of(keyword == null ? "" : keyword), "검색어는 1~50자 글자로 입력하세요 (주소가 아니라 검색어).");
        }
        if (naverKeywordFile == null) return new AddResult(0, 0, 0, List.of(k), "네이버 검색어 파일을 준비하지 못했습니다.");
        if (!naverKeywords.add(k)) return new AddResult(0, 0, 1, List.of(), "이미 있는 검색어입니다.");
        try {
            save(naverKeywordFile, naverKeywordHeader, naverKeywords);
        } catch (IOException e) {
            return new AddResult(0, 0, 0, List.of(k), "파일 저장 실패: " + e.getMessage());
        }
        return new AddResult(1, 0, 0, List.of(), "네이버 검색어 1개 추가");
    }

    private static void copyDefault(String classpath, Path target) throws IOException {
        ClassPathResource r = new ClassPathResource(classpath);
        String content = r.exists() ? r.getContentAsString(StandardCharsets.UTF_8) : "";
        Files.writeString(target, content, StandardCharsets.UTF_8);
    }

    private static void read(Path file, List<String> header, Set<String> into) throws IOException {
        header.clear();
        into.clear();
        boolean top = true;
        for (String raw : Files.readAllLines(file, StandardCharsets.UTF_8)) {
            String line = raw.strip();
            if (line.isEmpty() || line.startsWith("#")) {
                if (top) header.add(raw);
                continue;
            }
            top = false;
            into.add(line);
        }
    }

    private static void save(Path file, List<String> header, Set<String> lines) throws IOException {
        StringBuilder sb = new StringBuilder();
        header.forEach(h -> sb.append(h).append('\n'));
        lines.forEach(l -> sb.append(l).append('\n'));
        Path tmp = file.resolveSibling(file.getFileName() + ".tmp");
        Files.writeString(tmp, sb.toString(), StandardCharsets.UTF_8);
        Files.move(tmp, file, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
    }

    public synchronized List<String> listings() {
        return List.copyOf(listings);
    }

    public synchronized List<String> seeds() {
        return List.copyOf(seeds);
    }

    public synchronized List<String> tistoryKeywords() {
        return List.copyOf(tistoryKeywords);
    }

    /** 티스토리 검색어 1개 추가 */
    public synchronized AddResult addTistoryKeyword(String keyword) {
        String k = keyword == null ? "" : keyword.strip().replaceAll("\\s+", " ");
        if (k.isEmpty() || k.length() > 50 || k.startsWith("http")) {
            return new AddResult(0, 0, 0, List.of(keyword == null ? "" : keyword), "검색어는 1~50자 글자로 입력하세요 (주소가 아니라 검색어).");
        }
        if (!tistoryKeywords.add(k)) return new AddResult(0, 0, 1, List.of(), "이미 있는 검색어입니다.");
        try {
            save(tistoryKeywordFile, tistoryKeywordHeader, tistoryKeywords);
        } catch (IOException e) {
            return new AddResult(0, 0, 0, List.of(k), "파일 저장 실패: " + e.getMessage());
        }
        return new AddResult(1, 0, 0, List.of(), "티스토리 검색어 1개 추가");
    }

    public Path listingPath() {
        return listingFile;
    }

    public Path seedPath() {
        return seedFile;
    }

    /** velog 검색어 1개 추가 → 검색 화면 주소로 만들어 목록에 넣는다 */
    public synchronized AddResult addVelogKeyword(String keyword) {
        String k = keyword == null ? "" : keyword.strip().replaceAll("\\s+", " ");
        if (k.isEmpty() || k.length() > 50) {
            return new AddResult(0, 0, 0, List.of(keyword == null ? "" : keyword), "검색어는 1~50자로 입력하세요.");
        }
        return addUrls(VELOG_SEARCH + k);
    }

    /**
     * 여러 줄 주소 추가. 글 주소는 글 주소 목록으로, velog 태그·검색 화면과 티스토리 RSS 는 목록 주소로 분류한다.
     * velog·티스토리가 아니거나 형식이 다르면 넣지 않는다.
     */
    public synchronized AddResult addUrls(String text) {
        int addedL = 0, addedS = 0, dup = 0;
        List<String> invalid = new ArrayList<>();
        for (String raw : (text == null ? "" : text).split("\\R")) {
            String line = raw.strip();
            if (line.isEmpty() || line.startsWith("#")) continue;
            String kind = classify(line);
            if (kind == null) {
                invalid.add(line);
                continue;
            }
            if ("SEED".equals(kind)) {
                String url = UrlText.canonical(line);
                if (seeds.add(url)) addedS++; else dup++;
            } else {
                if (listings.add(line)) addedL++; else dup++;
            }
        }
        try {
            if (addedL > 0) save(listingFile, listingHeader, listings);
            if (addedS > 0) save(seedFile, seedHeader, seeds);
        } catch (IOException e) {
            return new AddResult(0, 0, dup, invalid, "파일 저장 실패: " + e.getMessage());
        }
        String msg = "목록 주소 " + addedL + "개, 글 주소 " + addedS + "개 추가 · 이미 있음 " + dup + "개"
                + (invalid.isEmpty() ? "" : " · 넣지 않음 " + invalid.size() + "개 (velog·티스토리·디시 글 주소, velog 태그·검색 화면, 티스토리 RSS, 디시 미니갤 목록만 가능)");
        return new AddResult(addedL, addedS, dup, invalid, msg);
    }

    /** SEED(글 주소) / LISTING(목록 주소) / null(넣을 수 없음) */
    static String classify(String line) {
        Optional<ReviewSite> site = ReviewSite.of(line);
        if (site.isEmpty()) return null;
        if (site.get().isPostUrl(UrlText.canonical(line))) return "SEED";
        URI uri;
        try {
            uri = URI.create(UrlText.toAscii(line));
        } catch (IllegalArgumentException e) {
            return null;
        }
        String path = uri.getPath() == null ? "" : uri.getPath();
        if (site.get() == ReviewSite.VELOG && (path.startsWith("/tags/") || (path.equals("/search") && uri.getRawQuery() != null)))
            return "LISTING";
        if (site.get() == ReviewSite.TISTORY && path.equals("/rss")) return "LISTING";
        // [11-14] 디시 마이너 갤러리 목록: /mini/board/lists/?id=갤러리
        if (site.get() == ReviewSite.DCINSIDE && path.startsWith("/mini/board/lists")
                && uri.getRawQuery() != null && uri.getRawQuery().contains("id=")) return "LISTING";
        return null;
    }

    /** 목록·글 주소에서 1개 삭제 */
    public synchronized boolean remove(String url) {
        String u = url == null ? "" : url.strip();
        try {
            if (u.startsWith(TISTORY_SEARCH)) {
                String k = java.net.URLDecoder.decode(u.substring(TISTORY_SEARCH.length()), StandardCharsets.UTF_8);
                if (tistoryKeywords.remove(k) || tistoryKeywords.remove(u.substring(TISTORY_SEARCH.length()))) {
                    save(tistoryKeywordFile, tistoryKeywordHeader, tistoryKeywords);
                    return true;
                }
                return false;
            }
            if (u.startsWith(NAVER_SEARCH) && naverKeywordFile != null) {
                String k = java.net.URLDecoder.decode(u.substring(NAVER_SEARCH.length()), StandardCharsets.UTF_8);
                if (naverKeywords.remove(k) || naverKeywords.remove(u.substring(NAVER_SEARCH.length()))) {
                    save(naverKeywordFile, naverKeywordHeader, naverKeywords);
                    return true;
                }
                return false;
            }
            if (listings.remove(u)) {
                save(listingFile, listingHeader, listings);
                return true;
            }
            if (seeds.remove(u) || seeds.remove(UrlText.canonical(u))) {
                save(seedFile, seedHeader, seeds);
                return true;
            }
        } catch (IOException e) {
            log.warn("수집 범위 저장 실패: {}", e.getMessage());
        }
        return false;
    }
}
