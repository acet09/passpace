package com.passpace.collect.client;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/**
 * [용성] robots.txt 해석 (RFC 9309 의 핵심 규칙만).
 *  - 우리 봇 이름(PasspaceStudentBot) 묶음이 있으면 그것을, 없으면 User-agent: * 묶음을 쓴다
 *  - Allow / Disallow 중 가장 길게 일치하는 규칙이 이긴다 (길이가 같으면 Allow)
 *  - 경로의 * (아무 글자)와 끝의 $ (경로 끝) 를 지원
 *  - Crawl-delay(초) 가 있으면 읽어 둔다 → ReviewPageFetcher 가 사이트 간격보다 크면 이 값을 쓴다
 */
public final class RobotsRules {

    private record Rule(boolean allow, String raw, Pattern pattern) {
    }

    private final List<Rule> rules;
    private final long crawlDelayMs;

    private RobotsRules(List<Rule> rules, long crawlDelayMs) {
        this.rules = rules;
        this.crawlDelayMs = crawlDelayMs;
    }

    public static RobotsRules allowAll() {
        return new RobotsRules(List.of(), 0);
    }

    public static RobotsRules disallowAll() {
        return new RobotsRules(List.of(rule(false, "/")), 0);
    }

    /** robots.txt 의 Crawl-delay (밀리초, 없으면 0) */
    public long crawlDelayMs() {
        return crawlDelayMs;
    }

    public static RobotsRules parse(String robotsTxt, String botToken) {
        List<Rule> mine = new ArrayList<>();
        List<Rule> star = new ArrayList<>();
        boolean foundMine = false;
        long mineDelay = 0, starDelay = 0;

        List<String> agents = new ArrayList<>();
        boolean readingAgents = false;
        for (String rawLine : robotsTxt.split("\\R")) {
            String line = rawLine.replaceAll("#.*$", "").strip();
            int colon = line.indexOf(':');
            if (colon < 0) continue;
            String key = line.substring(0, colon).strip().toLowerCase();
            String value = line.substring(colon + 1).strip();
            if (key.equals("user-agent")) {
                if (!readingAgents) agents = new ArrayList<>();
                agents.add(value.toLowerCase());
                readingAgents = true;
                continue;
            }
            readingAgents = false;
            boolean forMe = agents.stream().anyMatch(a -> !a.equals("*") && botToken.toLowerCase().contains(a));
            if (key.equals("crawl-delay")) {
                long ms = parseDelayMs(value);
                if (forMe) {
                    foundMine = true;
                    mineDelay = Math.max(mineDelay, ms);
                }
                if (agents.contains("*")) starDelay = Math.max(starDelay, ms);
                continue;
            }
            if (!key.equals("allow") && !key.equals("disallow")) continue;
            if (key.equals("disallow") && value.isEmpty()) continue;     // "Disallow:" 빈 값 = 제한 없음
            Rule r = rule(key.equals("allow"), value);
            if (forMe) {
                foundMine = true;
                mine.add(r);
            }
            if (agents.contains("*")) star.add(r);
        }
        return foundMine ? new RobotsRules(mine, mineDelay) : new RobotsRules(star, starDelay);
    }

    /** "2", "0.5" 같은 초 단위 → 밀리초 (해석 불가면 0) */
    private static long parseDelayMs(String value) {
        try {
            double sec = Double.parseDouble(value.strip());
            return sec > 0 ? Math.round(sec * 1000) : 0;
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    /** path 는 인코딩된 경로 + (있으면) ?query */
    public boolean isAllowed(String path) {
        Rule best = null;
        for (Rule r : rules) {
            if (!r.pattern.matcher(path).lookingAt()) continue;
            if (best == null || r.raw.length() > best.raw.length()
                    || (r.raw.length() == best.raw.length() && r.allow)) {
                best = r;
            }
        }
        return best == null || best.allow;
    }

    private static Rule rule(boolean allow, String raw) {
        StringBuilder regex = new StringBuilder();
        String body = raw.endsWith("$") ? raw.substring(0, raw.length() - 1) : raw;
        for (String part : body.split("\\*", -1)) {
            if (regex.length() > 0) regex.append(".*");
            regex.append(Pattern.quote(part));
        }
        if (raw.endsWith("$")) regex.append("$");
        return new Rule(allow, raw, Pattern.compile(regex.toString()));
    }
}
