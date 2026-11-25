package com.passpace.user.withdrawal;

import com.passpace.constant.MajorType;
import com.passpace.error.ErrorCode;
import com.passpace.error.exception.UserException;
import com.passpace.jwt.JwtPrincipal;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.TransientDataAccessResourceException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class AccountWithdrawalServiceTest {
    private final AccountWithdrawalRepository repository = mock(AccountWithdrawalRepository.class);
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(4);
    private final JwtPrincipal principal = new JwtPrincipal(42L, "SAMPLE_MEMBER", "SAMPLE", MajorType.MAJOR, "ADMIN");
    private AccountWithdrawalService service;
    private String originalHash;

    @BeforeEach
    void setUp() {
        originalHash = encoder.encode("SAMPLE_password");
        service = new AccountWithdrawalService(repository, encoder);
        when(repository.lockMember(42L)).thenReturn(Optional.of(new AccountWithdrawalRepository.Member(
                42L, "SAMPLE_MEMBER", originalHash, "MAJOR")));
        when(repository.withdraw(42L, "SAMPLE_MEMBER")).thenReturn(1);
    }

    private WithdrawalDtos.Request valid() {
        return new WithdrawalDtos.Request("SAMPLE_password", "SAMPLE_MEMBER회원탈퇴", true);
    }

    private void assertCode(ErrorCode code, Runnable operation) {
        assertEquals(code, assertThrows(UserException.class, operation::run).getErrorCode());
    }

    @Test
    void currentPasswordAndExactConfirmationDeleteOnlyAuthenticatedIdentity() {
        service.withdraw(principal, valid());
        verify(repository).lockMember(42L);
        verify(repository).withdraw(42L, "SAMPLE_MEMBER");
        verifyNoMoreInteractions(repository);
    }

    @Test
    void wrongPasswordDoesNotChangeAccount() {
        assertCode(ErrorCode.INVALID_REQUEST, () -> service.withdraw(principal,
                new WithdrawalDtos.Request("SAMPLE_wrong", "SAMPLE_MEMBER회원탈퇴", true)));
        verify(repository, never()).withdraw(anyLong(), anyString());
    }

    @Test
    void confirmationRequiresOwnIdWithoutParenthesesAndExactSpacing() {
        for (String value : new String[]{"회원탈퇴", "(SAMPLE_MEMBER)회원탈퇴", "SAMPLE_OTHER회원탈퇴",
                "sample_member회원탈퇴", " SAMPLE_MEMBER회원탈퇴", "SAMPLE_MEMBER회원탈퇴 ", ""}) {
            assertCode(ErrorCode.INVALID_REQUEST, () -> service.withdraw(principal,
                    new WithdrawalDtos.Request("SAMPLE_password", value, true)));
        }
        verify(repository, never()).withdraw(anyLong(), anyString());
    }

    @Test
    void blankOrOver72BytePasswordIsRejectedBeforeStorage() {
        for (String value : new String[]{"", " ", "a".repeat(73), "한".repeat(25)}) {
            assertCode(ErrorCode.INVALID_REQUEST, () -> service.withdraw(principal,
                    new WithdrawalDtos.Request(value, "SAMPLE_MEMBER회원탈퇴", true)));
        }
        verifyNoInteractions(repository);
    }

    @Test
    void missingAuthenticationCannotWithdraw() {
        assertCode(ErrorCode.FAILURE_JWT_VERIFIED, () -> service.withdraw(null, valid()));
        verifyNoInteractions(repository);
    }

    @Test
    void missingMemberAndChangedIdentityAreNotAccepted() {
        when(repository.lockMember(42L)).thenReturn(Optional.empty());
        assertCode(ErrorCode.FAILURE_JWT_VERIFIED, () -> service.withdraw(principal, valid()));
        when(repository.lockMember(42L)).thenReturn(Optional.of(new AccountWithdrawalRepository.Member(
                42L, "SAMPLE_CHANGED", originalHash, "MAJOR")));
        assertCode(ErrorCode.FAILURE_JWT_VERIFIED, () -> service.withdraw(principal, valid()));
        verify(repository, never()).withdraw(anyLong(), anyString());
    }

    @Test
    void alreadyWithdrawnMemberCannotBeWithdrawnAgain() {
        when(repository.lockMember(42L)).thenReturn(Optional.of(new AccountWithdrawalRepository.Member(
                42L, AccountWithdrawalRepository.withdrawnLoginId(42L), originalHash, null)));
        assertCode(ErrorCode.FAILURE_JWT_VERIFIED, () -> service.withdraw(principal, valid()));
        verify(repository, never()).withdraw(anyLong(), anyString());
    }

    @Test
    void changedOrUnknownMajorRequiresFreshLogin() {
        for (String value : new String[]{"NON_MAJOR", "INVALID"}) {
            when(repository.lockMember(42L)).thenReturn(Optional.of(new AccountWithdrawalRepository.Member(
                    42L, "SAMPLE_MEMBER", originalHash, value)));
            assertCode(ErrorCode.FORBIDDEN_ACCESS, () -> service.withdraw(principal, valid()));
        }
        verify(repository, never()).withdraw(anyLong(), anyString());
    }

    @Test
    void concurrentChangesAndDatabaseFailureDoNotReportSuccess() {
        when(repository.withdraw(eq(42L), anyString())).thenReturn(0);
        assertCode(ErrorCode.DATA_INTEGRITY_VIOLATION, () -> service.withdraw(principal, valid()));
        doThrow(new TransientDataAccessResourceException("SAMPLE contention")).when(repository).lockMember(42L);
        assertCode(ErrorCode.DATA_INTEGRITY_VIOLATION, () -> service.withdraw(principal, valid()));
        doThrow(new DataAccessResourceFailureException("SAMPLE unavailable")).when(repository).lockMember(42L);
        assertCode(ErrorCode.SERVICE_UNAVAILABLE, () -> service.withdraw(principal, valid()));
    }

    @Test
    void deletionConsentIsRequiredBeforeLookingUpAnyMember() {
        assertCode(ErrorCode.INVALID_REQUEST, () -> service.withdraw(principal,
                new WithdrawalDtos.Request("SAMPLE_password", "SAMPLE_MEMBER회원탈퇴", false)));
        verifyNoInteractions(repository);
    }

    @Test
    void foreignKeyConflictNeverReportsSuccessfulDeletion() {
        doThrow(new DataIntegrityViolationException("SAMPLE foreign ownership")).when(repository)
                .withdraw(42L, "SAMPLE_MEMBER");
        assertCode(ErrorCode.DATA_INTEGRITY_VIOLATION, () -> service.withdraw(principal, valid()));
    }

    @Test
    void credentialsAreNotIncludedInRequestOrMemberToString() {
        assertFalse(valid().toString().contains("SAMPLE_password"));
        assertFalse(new AccountWithdrawalRepository.Member(42, "SAMPLE", originalHash, "MAJOR")
                .toString().contains(originalHash));
        assertTrue(AccountWithdrawalRepository.withdrawnLoginId(Long.MAX_VALUE).length() <= 30);
    }
}
