package com.passpace.user.withdrawal;

import com.passpace.constant.MajorType;
import com.passpace.error.ErrorCode;
import com.passpace.error.exception.UserException;
import com.passpace.jwt.JwtPrincipal;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.TransientDataAccessException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.util.Objects;

/** [한결] 현재 비밀번호·명시적 동의를 확인하고 계정과 본인의 학습 데이터를 함께 삭제한다. */
@Service
public class AccountWithdrawalService {
    private final AccountWithdrawalRepository repository;
    private final BCryptPasswordEncoder encoder;

    public AccountWithdrawalService(AccountWithdrawalRepository repository, BCryptPasswordEncoder encoder) {
        this.repository = repository;
        this.encoder = encoder;
    }

    @Transactional
    public void withdraw(JwtPrincipal principal, WithdrawalDtos.Request request) {
        if (principal == null || principal.getUserId() == null || principal.getUserId() <= 0 ||
                principal.getLoginId() == null || AccountWithdrawalRepository.isWithdrawn(principal.getLoginId())) {
            throw new UserException(ErrorCode.FAILURE_JWT_VERIFIED);
        }
        if (request == null || !request.deletePersonalData()) {
            throw invalid("계정과 학습 자료의 영구 삭제 확인이 필요합니다. 최신 앱에서 다시 확인해 주세요.");
        }
        if (request.password() == null || request.password().isBlank() ||
                request.password().length() > 72 ||
                request.password().getBytes(StandardCharsets.UTF_8).length > 72) {
            throw invalid("비밀번호를 확인해 주세요.");
        }
        try {
            var member = repository.lockMember(principal.getUserId()).orElseThrow(
                    () -> new UserException(ErrorCode.FAILURE_JWT_VERIFIED));
            if (AccountWithdrawalRepository.isWithdrawn(member.loginId()) ||
                    member.userId() != principal.getUserId() ||
                    !Objects.equals(member.loginId(), principal.getLoginId())) {
                throw new UserException(ErrorCode.FAILURE_JWT_VERIFIED);
            }
            MajorType actualMajor = MajorType.fromCode(member.majorCode());
            if (member.majorCode() != null && actualMajor == null ||
                    !Objects.equals(actualMajor, principal.getMajorType())) {
                throw new UserException(ErrorCode.FORBIDDEN_ACCESS, "회원정보가 변경됐습니다. 다시 로그인해 주세요.");
            }
            if (!(member.loginId() + "회원탈퇴").equals(request.confirmation())) {
                throw invalid("회원탈퇴 확인 문구가 일치하지 않습니다.");
            }
            if (member.passwordHash() == null || !encoder.matches(request.password(), member.passwordHash())) {
                throw invalid("비밀번호가 일치하지 않습니다.");
            }
            if (repository.withdraw(member.userId(), member.loginId()) != 1) {
                throw new UserException(ErrorCode.DATA_INTEGRITY_VIOLATION,
                        "계정 상태가 변경됐습니다. 다시 로그인해 확인해 주세요.");
            }
        } catch (TransientDataAccessException e) {
            throw new UserException(ErrorCode.DATA_INTEGRITY_VIOLATION,
                    "다른 작업과 겹쳤습니다. 계정 상태를 확인한 뒤 다시 시도해 주세요.");
        } catch (DataIntegrityViolationException e) {
            throw new UserException(ErrorCode.DATA_INTEGRITY_VIOLATION,
                    "연결된 자료의 상태를 확인할 수 없어 탈퇴를 취소했습니다. 계정 정보를 확인해 주세요.");
        } catch (DataAccessException e) {
            throw new UserException(ErrorCode.SERVICE_UNAVAILABLE,
                    "회원탈퇴를 처리하지 못했습니다. 잠시 후 다시 확인해 주세요.");
        }
    }

    private UserException invalid(String message) {
        return new UserException(ErrorCode.INVALID_REQUEST, message);
    }
}
