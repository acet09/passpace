package com.passpace.service;

import com.passpace.dto.collect.CollectDtos.QualityResult;
import com.passpace.constant.ReviewStatus;
import com.passpace.domain.ExtractedReview;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.regex.Pattern;

/**
 * [용성] 후기 정제·검증 규칙 (기획안 7.1.3)
 *  - 광고·협찬 글 제외
 *  - 시간 정보가 전혀 없는 글 제외
 *  - 이상값: 하루 20시간 이상, 총 5시간 미만
 *  - 합격 여부를 알 수 없으면 PENDING (사람이 확인)
 *  - (크롤링 글) 최근 3년·작성일·전재 금지·공식 일정 대조 (기획안 7.1.1~7.1.3)
 */
@Component
public class ReviewQualityChecker {

    private static final Pattern AD = Pattern.compile("협찬|광고|할인\\s*코드|제공받아|원고료|쿠폰");

    /** 수집 정책 확인에 필요한 글 밖의 정보 */
    public record PageContext(LocalDate postedAt, LocalDate today, boolean noReprint, LocalDate officialExamDate) {
    }

    public static final int MAX_AGE_YEARS = 3;

    /**
     * 크롤링 글 전체 검사 = 정책 검사(작성일·전재 금지·일정 대조) → 내용 검사 → 시험 구분 확인
     *  - 작성일을 모르면 "최근 3년" 조건을 확인할 수 없으므로 제외
     *  - 응시 연도가 작성일보다 뒤 / 공식 시험일보다 먼저 쓴 합격 후기 → 날짜 모순으로 제외
     *  - 필기·실기를 알 수 없으면 PENDING (사람이 확인 후 VALID 로 바꿀 수 있음)
     */
    public QualityResult check(ExtractedReview r, String text, PageContext ctx) {
        if (ctx.noReprint()) {
            return excluded("무단 전재·복제 금지 표시");
        }
        if (ctx.postedAt() == null) {
            return excluded("작성일 확인 불가 (최근 3년 조건 확인 불가)");
        }
        if (ctx.postedAt().isBefore(ctx.today().minusYears(MAX_AGE_YEARS))) {
            return excluded("작성일이 3년보다 오래됨 (" + ctx.postedAt() + ")");
        }
        if (ctx.postedAt().isAfter(ctx.today().plusDays(1))) {
            return excluded("날짜 모순: 작성일이 미래");
        }
        if (r.examYear() != null && r.examYear() > ctx.postedAt().getYear()) {
            return excluded("날짜 모순: 응시 연도(" + r.examYear() + ")가 작성일보다 뒤");
        }
        if (ctx.officialExamDate() != null && Boolean.TRUE.equals(r.passed())
                && ctx.postedAt().isBefore(ctx.officialExamDate())) {
            return excluded("날짜 모순: 공식 시험일(" + ctx.officialExamDate() + ") 이전에 쓴 합격 후기");
        }
        QualityResult base = check(r, text);
        if (!ReviewStatus.VALID.name().equals(base.reviewStatus())) {
            return base;
        }
        if (r.examType() == null) {
            return new QualityResult(ReviewStatus.PENDING.name(), "필기·실기 구분 불가 - 확인 필요");
        }
        return base;
    }

    /** 내용만 보는 검사 (광고·시간 정보·이상값·합격 여부) */
    public QualityResult check(ExtractedReview r, String text) {
        if (text != null && AD.matcher(text).find()) {
            return excluded("광고·협찬 의심");
        }
        if (r.prepDays() == null && r.dailyMinutes() == null && r.totalHours() == null) {
            return excluded("시간 정보 없음");
        }
        if (r.dailyMinutes() != null && r.dailyMinutes() >= 20 * 60) {
            return excluded("이상값: 하루 20시간 이상");
        }
        if (r.totalHours() != null && r.totalHours().compareTo(BigDecimal.valueOf(5)) < 0) {
            return excluded("이상값: 총 공부시간 5시간 미만");
        }
        if (r.passed() == null) {
            return new QualityResult(ReviewStatus.PENDING.name(), "합격 여부 불명 - 확인 필요");
        }
        return new QualityResult(ReviewStatus.VALID.name(), null);
    }

    /**
     * [11-14] 네이버 검색 API 요약문(제목 + 1~2문장) 전용 검사. 기존 check(...) 는 그대로 둔다.
     *  - 광고·이상값만 EXCLUDED (기존 규칙 재사용)
     *  - 그 밖은 모두 PENDING: 요약문은 잘려 있어 시간·합격 정보를 잘못 읽을 위험이 크고,
     *    작성일이 없으면(카페) 통계 쿼리의 "최근 3년" 조건을 그냥 통과하므로 VALID 로는 절대 저장하지 않는다
     */
    public QualityResult checkSnippet(ExtractedReview r, String text, LocalDate postedAt) {
        if (text != null && AD.matcher(text).find()) {
            return excluded("광고·협찬 의심");
        }
        if (r.dailyMinutes() != null && r.dailyMinutes() >= 20 * 60) {
            return excluded("이상값: 하루 20시간 이상");
        }
        if (r.totalHours() != null && r.totalHours().compareTo(BigDecimal.valueOf(5)) < 0) {
            return excluded("이상값: 총 공부시간 5시간 미만");
        }
        return new QualityResult(ReviewStatus.PENDING.name(), postedAt == null ? "작성일 없음·요약문만 수집" : "요약문만 수집");
    }

    private static QualityResult excluded(String reason) {
        return new QualityResult(ReviewStatus.EXCLUDED.name(), reason);
    }
}
