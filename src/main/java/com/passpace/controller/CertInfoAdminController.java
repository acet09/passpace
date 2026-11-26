package com.passpace.controller;

import com.passpace.dto.ResponseDto;
import com.passpace.service.CertInfoCollectService;
import com.passpace.util.ResponseUtil;
import io.swagger.v3.oas.annotations.Operation;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/** [11-26] 관리자: 자격증 정보 메뉴 값 수집 (/admin/collect/** 는 ADMIN 만) */
@RestController
@RequestMapping("/admin/collect")
public class CertInfoAdminController {

    private final CertInfoCollectService service;

    public CertInfoAdminController(CertInfoCollectService service) {
        this.service = service;
    }

    @Operation(summary = "자격증 정보 수집", description = "큐넷 자격정보·합격률·산업안전기사 일정을 수집. 수집 안 되는 값은 db/14 고정값 유지")
    @PostMapping("/cert-info")
    public ResponseEntity<ResponseDto<Map<String, List<String>>>> collect() {
        return ResponseUtil.SUCCESS(Map.of("lines", service.collect()));
    }
}
