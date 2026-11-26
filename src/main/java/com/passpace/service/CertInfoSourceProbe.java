package com.passpace.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * [11-26] 자격증 정보 메뉴 값을 "수집"으로 채울 수 있는지 보는 1단계: 출처 응답 원본 저장.
 * collect-data/certinfo/run.txt 가 생기면 적힌 출처를 한 번씩 불러 collect-data/certinfo/raw/ 에 그대로 저장한다.
 * 응답 모양을 확인한 뒤 2단계에서 파싱해 CERTIFICATION_INFO·CERTIFICATION_EXAM_INFO·EXAM_ROUNDS 에 넣는다.
 * DB 는 건드리지 않는다. 인증키는 passpace.collect.data-go-kr-key (파일·로그에 키를 남기지 않음).
 */
@Component
public class CertInfoSourceProbe {

    private static final Logger log = LoggerFactory.getLogger(CertInfoSourceProbe.class);

    private final String serviceKey;
    private final Path dir;
    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(15))
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();

    public CertInfoSourceProbe(@Value("${passpace.collect.data-go-kr-key:}") String serviceKey,
                               @Value("${passpace.collect.data-dir:collect-data}") String dataDir) {
        this.serviceKey = serviceKey == null ? "" : serviceKey.trim();
        this.dir = Paths.get(dataDir).toAbsolutePath().normalize().resolve("certinfo");
    }

    @EventListener(ApplicationReadyEvent.class)
    public void startTriggerWatcher() {
        Thread w = new Thread(() -> {
            Path trigger = dir.resolve("run.txt");
            while (true) {
                try {
                    Thread.sleep(10_000L);
                    if (Files.exists(trigger)) {
                        List<String> lines = Files.readAllLines(trigger, StandardCharsets.UTF_8);
                        Files.move(trigger, trigger.resolveSibling("run.done"), StandardCopyOption.REPLACE_EXISTING);
                        run(lines);
                    }
                } catch (InterruptedException e) {
                    return;
                } catch (Exception e) {
                    log.warn("자격증 정보 출처 확인 실패: {}", e.getMessage());
                }
            }
        }, "certinfo-probe-trigger");
        w.setDaemon(true);
        w.start();
        try {
            Files.createDirectories(dir);
        } catch (IOException ignored) {
        }
        log.info("자격증 정보 출처 확인: 실행 신호 파일 대기 중 ({})", dir.resolve("run.txt"));
    }

    /**
     * 출처별 원본 응답을 raw/ 에 저장하고 요약(summary.txt)을 남긴다.
     * run.txt 에 줄이 있으면 그 목록을 쓴다: "파일이름|GET|주소" 또는 "파일이름|POST|주소|폼본문" ({KEY} = 인증키 자리)
     */
    public synchronized void run(List<String> lines) throws IOException {
        Path raw = dir.resolve("raw");
        Files.createDirectories(raw);
        String key = URLEncoder.encode(serviceKey, StandardCharsets.UTF_8);
        List<String> summary = new ArrayList<>();
        summary.add("# 자격증 정보 출처 확인 " + LocalDateTime.now() + " (인증키 " + (serviceKey.isEmpty() ? "없음" : "있음") + ")");
        for (String l : lines) {
            String[] p = l.split("\\|", 4);
            if (p.length < 3 || l.startsWith("#")) continue;
            String name = p[0].trim(), method = p[1].trim().toUpperCase(), url = p[2].trim().replace("{KEY}", key);
            String line;
            try {
                HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(url))
                        .timeout(Duration.ofSeconds(30))
                        .header("User-Agent", "Mozilla/5.0 (PasspaceStudentBot/0.1 school project)");
                if ("POST".equals(method)) {
                    b.header("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
                            .POST(HttpRequest.BodyPublishers.ofString(p.length > 3 ? p[3].trim() : "", StandardCharsets.UTF_8));
                } else {
                    b.GET();
                }
                HttpResponse<byte[]> res = http.send(b.build(), HttpResponse.BodyHandlers.ofByteArray());
                Files.write(raw.resolve(name), res.body());
                line = name + " | HTTP " + res.statusCode() + " | " + res.body().length + " bytes";
            } catch (Exception e) {
                line = name + " | 실패 " + e.getClass().getSimpleName() + ": " + e.getMessage();
            }
            summary.add(line);
            log.info("자격증 정보 출처 확인: {}", line);
        }
        Files.write(dir.resolve("summary.txt"), summary, StandardCharsets.UTF_8);
    }
}
