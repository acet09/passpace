package com.passpace.user.withdrawal;

import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.mockito.Mockito.mock;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Same DELETE regression that returned405 before the feature was present. */
class WithdrawalEndpointBaselineTest {
    @Test
    void deleteMeAcceptsWithdrawalRequestsInsteadOfMethodNotAllowed() throws Exception {
        var mvc = MockMvcBuilders.standaloneSetup(new AccountWithdrawalController(
                mock(AccountWithdrawalService.class))).build();
        mvc.perform(delete("/users/me").contentType("application/json").content("{}"))
                .andExpect(status().isBadRequest());
    }
}
