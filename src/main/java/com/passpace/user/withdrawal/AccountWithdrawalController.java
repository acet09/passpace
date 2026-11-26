package com.passpace.user.withdrawal;

import com.passpace.error.ErrorCode;
import com.passpace.error.ErrorResponseDto;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.util.ResponseUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/** [한결] 기존 회원 API와 동일한 JWT/JSON 응답 규칙의 회원탈퇴. */
@RestController
@Tag(name = "회원탈퇴", description = "계정과 본인 학습계획·기록·대화 영구 삭제")
public class AccountWithdrawalController {
    private final AccountWithdrawalService service;

    public AccountWithdrawalController(AccountWithdrawalService service) {
        this.service = service;
    }

    @DeleteMapping("/users/me")
    @Operation(summary = "본인 회원탈퇴", description =
            "현재 비밀번호와 정확히 로그인아이디회원탈퇴 문구를 확인합니다. " +
            "deletePersonalData=true 확인 후 계정과 본인 계획·학습기록·대화·AI 제안을 함께 삭제하고 이전 토큰을 차단합니다.")
    public ResponseEntity<?> withdraw(@AuthenticationPrincipal JwtPrincipal principal,
                                      @RequestBody WithdrawalDtos.Request request) {
        service.withdraw(principal, request);
        return ResponseUtil.SUCCESS(new WithdrawalDtos.Response(true, true));
    }

    /** 바인딩 예외의 원문에는 비밀번호가 포함될 수 있어 이 API에서는 일반 메시지만 반환한다. */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<?> invalidBody(HttpMessageNotReadableException ignored) {
        return ResponseUtil.ERROR(400, new ErrorResponseDto(ErrorCode.INVALID_REQUEST,
                "비밀번호·확인 문구와 영구 삭제 동의를 확인해 주세요."));
    }
}
