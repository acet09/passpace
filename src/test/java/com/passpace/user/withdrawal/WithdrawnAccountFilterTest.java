package com.passpace.user.withdrawal;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.passpace.constant.MajorType;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.jwt.UserAuthentication;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class WithdrawnAccountFilterTest {
    private final AccountWithdrawalRepository repository = mock(AccountWithdrawalRepository.class);
    private final WithdrawnAccountFilter filter = new WithdrawnAccountFilter(repository, new ObjectMapper());

    @AfterEach
    void cleanup() { SecurityContextHolder.clearContext(); }

    private void authenticate(String loginId) {
        SecurityContextHolder.getContext().setAuthentication(new UserAuthentication(
                new JwtPrincipal(42L, loginId, "SAMPLE", MajorType.MAJOR, "ADMIN"), null, List.of()));
    }

    @Test
    void activeIdentityCanReachExistingProtectedApi() throws Exception {
        authenticate("SAMPLE_MEMBER");
        when(repository.isCurrentIdentity(42L, "SAMPLE_MEMBER")).thenReturn(true);
        var calls = new AtomicInteger();
        filter.doFilter(new MockHttpServletRequest("GET", "/study/sessions"), new MockHttpServletResponse(),
                (request, response) -> calls.incrementAndGet());
        assertEquals(1, calls.get());
    }

    @Test
    void oldIdentityIsRejectedAcrossMemberChatStudyAndAdminApis() throws Exception {
        for (String path : List.of("/auth/user-info", "/users/me/goal", "/api/chat", "/study/sessions",
                "/admin/collect/sources")) {
            authenticate("SAMPLE_MEMBER");
            var response = new MockHttpServletResponse();
            filter.doFilter(new MockHttpServletRequest("GET", path), response,
                    (request, next) -> fail("Revoked identity reached an existing API"));
            assertEquals(401, response.getStatus());
            assertEquals("ERROR", new ObjectMapper().readTree(response.getContentAsString()).get("status").asText());
            assertNull(response.getHeader("Location"));
        }
    }

    @Test
    void evenTokenForReservedClosedLoginCannotReopenAccount() throws Exception {
        authenticate(AccountWithdrawalRepository.withdrawnLoginId(42L));
        var response = new MockHttpServletResponse();
        filter.doFilter(new MockHttpServletRequest("GET", "/users/me/goal"), response,
                (request, next) -> fail("Reserved identity must remain closed"));
        assertEquals(401, response.getStatus());
        verifyNoInteractions(repository);
    }

    @Test
    void publicSignupAndLoginDoNotNeedAccountQuery() throws Exception {
        for (String path : List.of("/auth/signup", "/auth/login", "/login", "/css/auth.css")) {
            var calls = new AtomicInteger();
            filter.doFilter(new MockHttpServletRequest("GET", path), new MockHttpServletResponse(),
                    (request, response) -> calls.incrementAndGet());
            assertEquals(1, calls.get());
        }
        verifyNoInteractions(repository);
    }

    @Test
    void unavailableDatabaseFailsClosedWithJson503() throws Exception {
        authenticate("SAMPLE_MEMBER");
        when(repository.isCurrentIdentity(42L, "SAMPLE_MEMBER"))
                .thenThrow(new DataAccessResourceFailureException("SAMPLE private diagnostics"));
        var response = new MockHttpServletResponse();
        filter.doFilter(new MockHttpServletRequest("GET", "/study/sessions"), response,
                (request, next) -> fail("Unavailable identity lookup must not reach API"));
        assertEquals(503, response.getStatus());
        assertFalse(response.getContentAsString().contains("SAMPLE private diagnostics"));
    }
}
