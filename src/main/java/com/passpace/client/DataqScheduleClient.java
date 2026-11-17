package com.passpace.client;

import com.passpace.constant.ExamType;
import com.passpace.dto.collect.CollectDtos.ExamScheduleItem;
import com.passpace.error.exception.CollectException;
import org.jsoup.Connection;
import org.jsoup.HttpStatusException;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * [용성·11-14] 시험일정 2순위 크롤링: 데이터자격검정(dataq) 시험일정 페이지 (SQLD·ADsP)
 *  GET https://www.dataq.or.kr/www/accept/schedule.do
 *
 *  - jsoup 로 HTML 만 받는다. Selenium 등 브라우저 자동화는 쓰지 않는다
 *    (dataq 는 자동화 브라우저를 감지하면 /www/tracer/info.jsp "개발자 도구 감지" 로 보낸다. JS 를 실행하지 않는 요청은 영향 없음)
 *  - 날짜는 연도 없이 "1.5~9", "4.13~17", "9.18~9.22" 처럼 범위로 적혀 있다
 *    → 연도는 페이지의 "2026년도", 범위는 시작·종료로 나누고, 월이 빠진 끝값은 시작 월을 이어받는다
 *  - 표: "데이터분석 준전문가"(ADsP) / "SQL 개발자"(SQLD), 열 순서 원서접수 / 수험표발급 / 시험일 / 사전점수공개 및 재검토 / 합격발표
 *    → 수험표발급·사전점수공개 열은 EXAM_ROUNDS 에 넣을 칸이 없어 버린다
 * ※ 2026-11-14 PC 브라우저에서 확인한 구조 기준. 첫 실행 때 Java 로 받은 HTML 을 fixture 로 저장해 다시 확인할 것
 */
@Component
public class DataqScheduleClient {

    public static final String SCHEDULE_URL = "https://www.dataq.or.kr/www/accept/schedule.do";
    private static final Pattern YEAR = Pattern.compile("(20\\d{2})\\s*년도");
    private static final Pattern ROUND = Pattern.compile("제?\\s*(\\d{1,3})\\s*회");
    /** 월.일[~[월.]일] (요일 괄호는 미리 지움) */
    private static final Pattern RANGE = Pattern.compile("(\\d{1,2})\\.(\\d{1,2})(?:\\s*[~∼〜-]\\s*(?:(\\d{1,2})\\.)?(\\d{1,2}))?");
    private static final Pattern ADSP = Pattern.compile("(?i)ADsP|데이터\\s*분석\\s*준\\s*전문가");
    private static final Pattern SQLD = Pattern.compile("(?i)SQLD|SQL\\s*개발자");

    /** 페이지에서 읽은 회차 1개: code = SQLD / ADSP */
    public record DataqRound(String code, ExamScheduleItem item) {
    }

    private final String userAgent;

    public DataqScheduleClient(@Value("${passpace.collect.user-agent}") String userAgent) {
        this.userAgent = userAgent;
    }

    public String fetch() {
        try {
            Connection.Response res = Jsoup.connect(SCHEDULE_URL).userAgent(userAgent)
                    .header("Accept-Language", "ko-KR,ko;q=0.9").timeout(20_000).followRedirects(true).execute();
            if (res.url().toString().contains("/tracer/")) {
                throw new CollectException("BLOCKED", "dataq 가 자동 요청으로 판단해 안내 페이지로 보냈습니다: " + res.url());
            }
            return res.body();
        } catch (HttpStatusException e) {
            throw new CollectException("HTTP_" + e.getStatusCode(), "dataq 일정 페이지를 가져오지 못했습니다(" + e.getStatusCode() + ")");
        } catch (IOException e) {
            throw new CollectException("NETWORK", "dataq 연결 실패: " + e.getMessage());
        }
    }

    /** HTML → 회차 목록 (네트워크 없이 테스트 가능). 연도를 못 찾으면 fallbackYear */
    public static List<DataqRound> parse(String html, int fallbackYear) {
        Document doc = Jsoup.parse(html == null ? "" : html);
        Matcher ym = YEAR.matcher(doc.text());
        int year = ym.find() ? Integer.parseInt(ym.group(1)) : fallbackYear;
        Map<String, DataqRound> out = new LinkedHashMap<>();
        for (Element table : doc.select("table")) {
            String current = examOf(headingBefore(table));
            for (Element tr : table.select("tr")) {
                List<String> cells = tr.select("th, td").eachText();
                if (cells.isEmpty()) continue;
                String rowExam = examOf(String.join(" ", cells));
                if (rowExam != null) current = rowExam;
                int idx = roundIndex(cells);
                if (current == null || idx < 0) continue;
                Matcher rm = ROUND.matcher(cells.get(idx));
                if (!rm.find()) continue;
                int round = Integer.parseInt(rm.group(1));
                List<String> rest = cells.subList(idx + 1, cells.size());
                if (rest.size() < 3) continue;
                LocalDate[] reg = range(rest.get(0), year);
                LocalDate[] exam = range(rest.size() >= 3 ? rest.get(2) : "", year);
                LocalDate[] result = range(rest.size() >= 5 ? rest.get(4) : rest.get(rest.size() - 1), year);
                if (exam[0] == null) continue;
                String label = "ADSP".equals(current) ? "ADsP" : "SQLD";
                ExamScheduleItem item = new ExamScheduleItem(exam[0].getYear(), round, ExamType.WRITTEN,
                        reg[0], reg[1], exam[0], exam[0], result[0], label + " 제" + round + "회 (dataq 일정 페이지)");
                out.putIfAbsent(current + ":" + round, new DataqRound(current, item));
            }
        }
        return new ArrayList<>(out.values());
    }

    private static String examOf(String s) {
        if (s == null) return null;
        if (ADSP.matcher(s).find()) return "ADSP";
        if (SQLD.matcher(s).find()) return "SQLD";
        return null;
    }

    /** 표 바로 앞 제목(h1~h5, strong, caption, p) 글자 */
    private static String headingBefore(Element table) {
        Element cap = table.selectFirst("caption");
        if (cap != null && examOf(cap.text()) != null) return cap.text();
        Element e = table.previousElementSibling();
        for (int i = 0; e != null && i < 3; i++, e = e.previousElementSibling()) {
            if (examOf(e.text()) != null) return e.text();
        }
        Element parent = table.parent();
        return parent == null ? null : parent.ownText();
    }

    /** "제51회" 처럼 회차가 적힌 칸의 위치 (날짜 칸보다 앞) */
    private static int roundIndex(List<String> cells) {
        for (int i = 0; i < cells.size(); i++) {
            String c = cells.get(i);
            if (ROUND.matcher(c).find() && !RANGE.matcher(c.replaceAll("\\([^)]*\\)", "")).find()) return i;
        }
        return -1;
    }

    /** "9.18~9.22", "1.5~9", "3.7(토)" → [시작, 끝]. 끝이 없으면 시작과 같다. 끝 월이 시작 월보다 작으면 다음 해 */
    static LocalDate[] range(String s, int year) {
        if (s == null) return new LocalDate[]{null, null};
        Matcher m = RANGE.matcher(s.replaceAll("\\([^)]*\\)", " "));
        if (!m.find()) return new LocalDate[]{null, null};
        try {
            int sm = Integer.parseInt(m.group(1)), sd = Integer.parseInt(m.group(2));
            LocalDate start = LocalDate.of(year, sm, sd);
            if (m.group(4) == null) return new LocalDate[]{start, start};
            int em = m.group(3) == null ? sm : Integer.parseInt(m.group(3));
            int ed = Integer.parseInt(m.group(4));
            LocalDate end = LocalDate.of(em < sm ? year + 1 : year, em, ed);
            return new LocalDate[]{start, end};
        } catch (Exception e) {
            return new LocalDate[]{null, null};
        }
    }
}
