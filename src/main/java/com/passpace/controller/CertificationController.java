package com.passpace.controller;

import com.passpace.dto.ResponseDto;
import com.passpace.dto.cert.CertificationViews.CertDetail;
import com.passpace.dto.cert.CertificationViews.CertSummary;
import com.passpace.service.CertificationInfoService;
import com.passpace.util.ResponseUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * [11-26] 지원 자격증 정보 메뉴 API (로그인 없이 열림 — SecurityPaths.PUBLIC, 개인 정보 없음).
 * 앱: 홈 "지원 자격증" 섹션, 자격증 목록, 자격증 상세, 학습계획 만들기의 ⓘ 요약 시트.
 */
@Tag(name = "지원 자격증 정보", description = "앱의 자격증 목록·상세 화면 (로그인 불필요)")
@RestController
@RequestMapping("/api/certifications")
public class CertificationController {

    private final CertificationInfoService service;

    public CertificationController(CertificationInfoService service) {
        this.service = service;
    }

    @Operation(summary = "지원 자격증 목록",
            description = "category(IT/데이터/사무·회계/안전)와 q(이름 검색)로 거를 수 있다. 다음 일정(D-day)이 가까운 순, 상시·일정 없음은 뒤로.")
    @GetMapping
    public ResponseEntity<ResponseDto<CertList>> list(@RequestParam(required = false) String category,
                                                      @RequestParam(required = false) String q) {
        return ResponseUtil.SUCCESS(new CertList(service.list(category, q)));
    }

    /** 목록 응답 data = { "certifications": [...] } (앱의 기존 응답 처리와 같은 객체 모양) */
    public record CertList(List<CertSummary> certifications) {
    }

    @Operation(summary = "지원 자격증 상세",
            description = "기본 정보, 필기/실기별 시험 정보(응시료·문항 수·시간·방식·합격 기준·과목), 응시자격, 알아두면 좋은 정보, 회차 일정, 최근 합격률, 공식 링크. 값이 없으면 null.")
    @GetMapping("/{id}")
    public ResponseEntity<ResponseDto<CertDetail>> detail(@PathVariable long id) {
        return service.detail(id)
                .map(ResponseUtil::SUCCESS)
                .orElseGet(() -> ResponseUtil.ERROR(404, null));
    }
}
