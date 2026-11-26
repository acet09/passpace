package com.passpace.service;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.time.LocalDate;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeoutException;

/** [11-24] CandidateProbeService 의 패키지 내부 메서드를 테스트에서 쓰기 위한 통로 (테스트 전용) */
public final class CandidateProbeServiceTestAccess {

    private CandidateProbeServiceTestAccess() {
    }

    private static CandidateProbeService.Candidate cert(String name) {
        return CandidateProbeService.CANDIDATES.get(name);
    }

    public static String classify(String cert, String title, String desc) {
        return CandidateProbeService.classify(cert(cert), title, desc).name();
    }

    public static boolean mixed(String cert, String text) {
        return CandidateProbeService.mentionsOther(cert(cert), text);
    }

    public static boolean containsWord(String haystack, String needle) {
        return CandidateProbeService.containsWord(haystack, needle);
    }

    public static long[] estimate(int population, int hits, int sampled) {
        return CandidateProbeService.estimate(population, hits, sampled);
    }

    public static String resolve(String nameOrCode) {
        return CandidateProbeService.resolve(nameOrCode);
    }

    public static String verdict(long expected) {
        return CandidateProbeService.verdict(expected);
    }

    /** 최근 3년 글 2건 + 오래된 글 3건 중 표본 2건 → 모두 최근 글이어야 한다 */
    public static boolean sampleTakesRecentFirst() {
        CandidateProbeService.CertStat s = CandidateProbeService.newStat(cert("산업안전기사"));
        LocalDate now = LocalDate.now();
        s.blogHits.add(new CandidateProbeService.Hit("https://blog.naver.com/a/1", false, "", "", now.minusYears(6)));
        s.blogHits.add(new CandidateProbeService.Hit("https://blog.naver.com/a/2", false, "", "", now.minusMonths(3)));
        s.blogHits.add(new CandidateProbeService.Hit("https://blog.naver.com/a/3", false, "", "", null));
        s.blogHits.add(new CandidateProbeService.Hit("https://blog.naver.com/a/4", false, "", "", now.minusYears(1)));
        s.blogHits.add(new CandidateProbeService.Hit("https://blog.naver.com/a/5", false, "", "", now.minusYears(5)));
        List<CandidateProbeService.Hit> picked = CandidateProbeService.pickSample(s, 2, 0, false);
        return picked.size() == 2 && picked.stream().allMatch(h -> h.postedAt != null && h.postedAt.isAfter(now.minusYears(3)));
    }

    /** 끝나지 않는 작업은 제한 시간 뒤 TimeoutException 으로 건너뛴다 */
    public static boolean timeoutSkips() throws Exception {
        ExecutorService ex = Executors.newSingleThreadExecutor();
        try {
            Future<String> f = ex.submit(() -> {
                Thread.sleep(2_000);
                return "늦음";
            });
            try {
                CandidateProbeService.await(f, 50);
                return false;
            } catch (TimeoutException e) {
                Future<String> ok = ex.submit(() -> "빠름");
                return f.isCancelled() && "빠름".equals(CandidateProbeService.await(ok, 1_000));
            }
        } finally {
            ex.shutdownNow();
        }
    }

    /** 생성자·필드에 리포지토리나 JdbcTemplate 이 없으면 DB 에 쓸 수 없다 */
    public static boolean hasNoRepositoryDependency() {
        for (Constructor<?> c : CandidateProbeService.class.getDeclaredConstructors()) {
            for (Class<?> p : c.getParameterTypes()) if (isDb(p)) return false;
        }
        for (Field f : CandidateProbeService.class.getDeclaredFields()) {
            if (isDb(f.getType())) return false;
        }
        return true;
    }

    private static boolean isDb(Class<?> t) {
        String n = t.getName();
        return n.startsWith("com.passpace.repository.") || n.contains("JdbcTemplate") || n.contains("DataSource")
                || n.contains("ReviewUrlLedger");
    }
}
