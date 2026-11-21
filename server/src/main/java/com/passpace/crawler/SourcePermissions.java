package com.passpace.crawler;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;

/**
 * [용성] 사이트별 수집 허용 확인 (기획안 7.1.2 "사이트별 이용약관·robots·AI 활용 권리 확인").
 *
 * DATA_SOURCES 의 source_type='CRAWL' 행 중 provider_name 이 사이트 이름과 같은 행을 본다.
 *  - 행이 없거나 active_yn 이 'Y' 가 아니면 → 수집 안 함
 *  - permission_checked_at 이 비어 있으면 → 아직 사람이 확인하지 않았으므로 수집 안 함
 * 확인을 마친 뒤 아래처럼 날짜를 넣으면 다음 실행부터 수집된다.
 *   UPDATE DATA_SOURCES SET permission_checked_at = NOW() WHERE provider_name = 'tistory';
 */
@Component
public class SourcePermissions {

    /** allowed=false 면 reason 에 이유 */
    public record Permission(ReviewSite site, Long sourceId, boolean allowed, String reason) {
    }

    private final JdbcTemplate jdbc;

    /**
     * [11-14] 크롤링 정책 폐기로 permission_checked_at 확인은 설정으로 끌 수 있게 했다 (기본 꺼짐).
     * 꺼져 있으면: 출처 행이 있으면 그 번호로 수집(비활성 행은 계속 건너뜀),
     *             출처 행이 없는 사이트는 건너뛰지 않고 sourceId=null 로 수집한다 (DATA_SOURCES 행 추가 안 함)
     */
    @Value("${passpace.collect.permission-check:false}")
    private boolean permissionCheck;

    public SourcePermissions(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Permission check(ReviewSite site) {
        List<Permission> rows = jdbc.query("""
                SELECT source_id, active_yn, permission_checked_at
                FROM DATA_SOURCES
                WHERE source_type = 'CRAWL' AND provider_name = ?
                ORDER BY source_id
                """, (rs, i) -> {
            long id = rs.getLong("source_id");
            if (!"Y".equals(rs.getString("active_yn"))) {
                return new Permission(site, id, false, site.providerName() + " 출처가 비활성(active_yn=N) 상태입니다.");
            }
            LocalDateTime checked = rs.getObject("permission_checked_at", LocalDateTime.class);
            if (checked == null && permissionCheck) {
                return new Permission(site, id, false, site.providerName()
                        + " 의 약관·robots.txt·AI 활용 허용 여부를 아직 확인하지 않았습니다 (DATA_SOURCES.permission_checked_at 비어 있음).");
            }
            return new Permission(site, id, true, null);
        }, site.providerName());
        if (rows.isEmpty()) {
            if (!permissionCheck) return new Permission(site, null, true, null);
            return new Permission(site, null, false, "DATA_SOURCES 에 " + site.providerName() + " 출처 행이 없습니다 (db/03_seed.sql).");
        }
        return rows.get(0);
    }
}
