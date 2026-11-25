package com.passpace.user.withdrawal;

import com.passpace.constant.MajorType;
import com.passpace.error.ErrorCode;
import com.passpace.error.GlobalExceptionHandler;
import com.passpace.error.exception.UserException;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.jwt.UserAuthentication;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.method.annotation.AuthenticationPrincipalArgumentResolver;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class AccountWithdrawalControllerTest {
    private final AccountWithdrawalService service = mock(AccountWithdrawalService.class);
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        SecurityContextHolder.getContext().setAuthentication(new UserAuthentication(
                new JwtPrincipal(42L, "SAMPLE_MEMBER", "SAMPLE", MajorType.MAJOR, "USER"), null, List.of()));
        mvc = MockMvcBuilders.standaloneSetup(new AccountWithdrawalController(service))
                .setCustomArgumentResolvers(new AuthenticationPrincipalArgumentResolver())
                .setControllerAdvice(new GlobalExceptionHandler()).build();
    }

    @AfterEach
    void cleanup() { SecurityContextHolder.clearContext(); }

    @Test
    void confirmedWithdrawalUsesExistingSuccessEnvelope() throws Exception {
        mvc.perform(delete("/users/me").contentType("application/json")
                        .content("{\"password\":\"SAMPLE_password\",\"confirmation\":\"SAMPLE_MEMBER회원탈퇴\",\"deletePersonalData\":true}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("SUCCESS"))
                .andExpect(jsonPath("$.code").value(200)).andExpect(jsonPath("$.data.withdrawn").value(true))
                .andExpect(jsonPath("$.data.personalDataDeleted").value(true));
        verify(service).withdraw(any(JwtPrincipal.class), any(WithdrawalDtos.Request.class));
    }

    @Test
    void previousRetentionClientWithoutExplicitDeletionConsentCannotWithdraw() throws Exception {
        mvc.perform(delete("/users/me").contentType("application/json")
                        .content("{\"password\":\"SAMPLE_password\",\"confirmation\":\"SAMPLE_MEMBER회원탈퇴\"}"))
                .andExpect(status().isBadRequest());
        verifyNoInteractions(service);
    }

    @Test
    void explicitDeletionConsentIsAcceptedAndConfirmedInResponse() throws Exception {
        mvc.perform(delete("/users/me").contentType("application/json")
                        .content("{\"password\":\"SAMPLE_password\",\"confirmation\":\"SAMPLE_MEMBER회원탈퇴\",\"deletePersonalData\":true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.withdrawn").value(true))
                .andExpect(jsonPath("$.data.personalDataDeleted").value(true));
    }

    @Test
    void malformedMissingNumericAndExtraInputsAreRejectedBeforeService() throws Exception {
        for (String body : new String[]{"{}", "[]", "null", "{", "{\"password\":123,\"confirmation\":\"x\"}",
                "{\"password\":\"SAMPLE_password\",\"confirmation\":\"x\",\"deletePersonalData\":true,\"userId\":9}"}) {
            mvc.perform(delete("/users/me").contentType("application/json").content(body))
                    .andExpect(status().isBadRequest()).andExpect(jsonPath("$.status").value("ERROR"));
        }
        verifyNoInteractions(service);
    }

    @Test
    void permanentDeletionConsentMustBeBooleanTrue() throws Exception {
        for (String value : new String[]{"false", "null", "\"true\"", "1", "{}", "[]"}) {
            mvc.perform(delete("/users/me").contentType("application/json")
                            .content("{\"password\":\"SAMPLE_password\",\"confirmation\":\"SAMPLE_MEMBER회원탈퇴\",\"deletePersonalData\":"+value+"}"))
                    .andExpect(status().isBadRequest());
        }
        verifyNoInteractions(service);
    }

    @Test
    void badPasswordRemainsJson400AndNeverReturnsWithdrawn() throws Exception {
        doThrow(new UserException(ErrorCode.INVALID_REQUEST, "비밀번호가 일치하지 않습니다."))
                .when(service).withdraw(any(), any());
        mvc.perform(delete("/users/me").contentType("application/json")
                        .content("{\"password\":\"SAMPLE_wrong\",\"confirmation\":\"SAMPLE_MEMBER회원탈퇴\",\"deletePersonalData\":true}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.data.withdrawn").doesNotExist());
    }
}
