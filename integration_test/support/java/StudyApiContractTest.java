package com.passpace.study;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.passpace.config.SecurityConfig;
import com.passpace.constant.MajorType;
import com.passpace.error.GlobalExceptionHandler;
import com.passpace.jwt.JwtAccessDeniedHandler;
import com.passpace.jwt.JwtAuthenticationEntryPoint;
import com.passpace.jwt.JwtPrincipal;
import com.passpace.jwt.JwtUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.FilterType;
import org.springframework.context.annotation.Import;
import org.springframework.context.support.PropertySourcesPlaceholderConfigurer;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.security.web.FilterChainProxy;
import org.springframework.test.context.ContextConfiguration;
import org.springframework.test.context.junit.jupiter.SpringExtension;
import org.springframework.test.context.web.WebAppConfiguration;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.EnableTransactionManagement;
import org.springframework.web.context.WebApplicationContext;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;

import javax.sql.DataSource;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.List;
import java.util.Properties;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.nullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ExtendWith(SpringExtension.class)
@ContextConfiguration(classes = StudyApiContractTest.TestConfig.class)
@WebAppConfiguration
class StudyApiContractTest {
    @Configuration
    @EnableWebMvc
    @EnableTransactionManagement
    @ComponentScan(basePackages = "com.passpace.study", excludeFilters =
            @ComponentScan.Filter(type = FilterType.ANNOTATION, classes = Configuration.class))
    @Import({SecurityConfig.class, JwtUtil.class, JwtAuthenticationEntryPoint.class,
            JwtAccessDeniedHandler.class, GlobalExceptionHandler.class})
    static class TestConfig implements org.springframework.web.servlet.config.annotation.WebMvcConfigurer {
        @Override
        public void addResourceHandlers(org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry registry) {
            registry.addResourceHandler("/**").addResourceLocations("classpath:/static/");
        }
        @Bean
        static PropertySourcesPlaceholderConfigurer properties() {
            byte[] bytes = new byte[64];
            new SecureRandom().nextBytes(bytes);
            Properties p = new Properties();
            p.setProperty("jwt.issuer", "isolated-study-api-test");
            p.setProperty("jwt.secret", Base64.getEncoder().encodeToString(bytes));
            p.setProperty("jwt.access-token-validity-in-seconds", "1800");
            var result = new PropertySourcesPlaceholderConfigurer();
            result.setProperties(p);
            return result;
        }
        @Bean
        DataSource dataSource() {
            String raw = System.getenv("STUDY_TEST_DB_PORT");
            if (raw == null) throw new IllegalStateException("isolated DB port required");
            int port = Integer.parseInt(raw);
            if (List.of(3306, 3308, 8080, 8082, 18080).contains(port))
                throw new IllegalStateException("production port forbidden");
            var ds = new DriverManagerDataSource(
                    "jdbc:mariadb://127.0.0.1:" + port + "/study_api_test", "root", "");
            String actual = new JdbcTemplate(ds).queryForObject("SELECT @@datadir", String.class);
            Path expected = Path.of(System.getenv("STUDY_TEST_DB_DATADIR")).toAbsolutePath().normalize();
            if (!expected.equals(Path.of(actual).toAbsolutePath().normalize()))
                throw new IllegalStateException("isolated database identity mismatch");
            return ds;
        }
        @Bean JdbcTemplate jdbcTemplate(DataSource ds) { return new JdbcTemplate(ds); }
        @Bean DataSourceTransactionManager transactionManager(DataSource ds) {
            return new DataSourceTransactionManager(ds);
        }
        @Bean Clock studyClock() {
            // UTC November 14 is already November 15 in Seoul.
            return Clock.fixed(Instant.parse("2026-11-14T15:30:00Z"), ZoneOffset.UTC);
        }
    }

    @Autowired WebApplicationContext context;
    @Autowired JdbcTemplate jdbc;
    @Autowired JwtUtil jwt;
    private MockMvc mvc;
    private String token;
    private final ObjectMapper json = new ObjectMapper();

    @BeforeEach
    void fixtures() {
        mvc = MockMvcBuilders.webAppContextSetup(context)
                .addFilters(context.getBean(FilterChainProxy.class)).build();
        jdbc.update("DELETE FROM STUDY_SESSIONS");
        jdbc.update("DELETE FROM STUDY_PLAN_DETAILS");
        jdbc.update("DELETE FROM STUDY_PLANS");
        jdbc.update("DELETE FROM USERS");
        jdbc.update("DELETE FROM CERTIFICATION_SUBJECTS");
        jdbc.update("DELETE FROM CERTIFICATIONS");
        jdbc.update("""
                INSERT INTO USERS(user_id,email,password_hash,major_type) VALUES
                (1,'sample-one@example.invalid','SAMPLE_NON_LOGIN_HASH','MAJOR'),
                (2,'sample-two@example.invalid','SAMPLE_NON_LOGIN_HASH','NON_MAJOR')
                """);
        jdbc.update("INSERT INTO CERTIFICATIONS(certification_id,cert_name) VALUES(1,'SAMPLE 시험')");
        jdbc.update("""
                INSERT INTO CERTIFICATION_SUBJECTS(certification_subject_id,certification_id,subject_name)
                VALUES(11,1,'SAMPLE 과목'),(12,1,'SAMPLE 다른 과목')
                """);
        jdbc.update("""
                INSERT INTO STUDY_PLANS(plan_id,user_id,version_no,status,start_date,end_date) VALUES
                (101,1,3,'ACTIVE','2026-11-01','2026-11-30'),
                (102,1,2,'REPLACED','2026-11-01','2026-11-30'),
                (201,2,1,'ACTIVE','2026-11-01','2026-11-30'),
                (103,1,4,'DRAFT','2026-11-01','2026-11-30')
                """);
        jdbc.update("""
                INSERT INTO STUDY_PLAN_DETAILS(task_id,user_id,plan_id,certification_subject_id,
                  subject_name,scheduled_date,estimated_minutes) VALUES
                (1001,1,101,11,'SAMPLE 과목','2026-11-14',60),
                (1002,1,101,NULL,'SAMPLE 임시 과목','2026-11-13',60),
                (1101,1,102,11,'SAMPLE 과목','2026-11-14',60),
                (2001,2,201,12,'SAMPLE 다른 과목','2026-11-14',60),
                (3001,1,201,12,'SAMPLE 잘못 연결된 항목','2026-11-14',60),
                (1003,1,103,11,'SAMPLE 초안','2026-11-14',60)
                """);
        token = jwt.createToken(new JwtPrincipal(1L, "sample-one", "SAMPLE", MajorType.MAJOR, "USER"));
    }

    @Test
    void authenticatedEmptyPeriodHasZeroActualMinutesAndCalendarDays() throws Exception {
        mvc.perform(get("/dashboard/study-stats")
                        .header("Authorization", "Bearer " + token)
                        .param("period", "CUSTOM").param("startDate", "2026-11-13")
                        .param("endDate", "2026-11-15"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.totalMinutes").value(0))
                .andExpect(jsonPath("$.data.dailyStudyMinutes", hasSize(3)))
                .andExpect(jsonPath("$.data.dailyStudyMinutes[0].studyDate").value("2026-11-13"))
                .andExpect(jsonPath("$.data.dailyStudyMinutes[1].durationMinutes").value(0))
                .andExpect(jsonPath("$.data.completionRate").value(nullValue()))
                .andExpect(jsonPath("$.data.timezone").value("Asia/Seoul"));
    }

    @Test
    void manualSaveRoundTripsWithoutInventingPlanOrClockTimes() throws Exception {
        MvcResult saved = create("""
                {"studyDate":"2026-11-14","durationMinutes":45}
                """, 200);
        long id = json.readTree(saved.getResponse().getContentAsString()).at("/data/sessionId").asLong();
        assertThat(id).isPositive();
        var row = jdbc.queryForMap("SELECT user_id,actual_minutes,task_id,start_time,end_time,input_method FROM STUDY_SESSIONS WHERE session_id=?", id);
        assertThat(((Number) row.get("user_id")).longValue()).isEqualTo(1);
        assertThat(((Number) row.get("actual_minutes")).intValue()).isEqualTo(45);
        assertThat(row.get("task_id")).isNull();
        assertThat(row.get("start_time")).isNull();
        assertThat(row.get("end_time")).isNull();
        assertThat(row.get("input_method")).isEqualTo("MANUAL");
        mvc.perform(list(0, 20)).andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items", hasSize(1)))
                .andExpect(jsonPath("$.data.items[0].durationMinutes").value(45))
                .andExpect(jsonPath("$.data.items[0].subjectId").value(nullValue()))
                .andExpect(jsonPath("$.data.hasNext").value(false));
    }

    @Test
    void plannedSaveChecksVersionAndDerivesOwnedPlanAndSubject() throws Exception {
        create("""
                {"studyDate":"2026-11-15","durationMinutes":30,"taskId":1001,
                 "expectedPlanVersion":3,"subjectId":11,"planId":101}
                """, 200);
        mvc.perform(list(0, 20)).andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items[0].planId").value(101))
                .andExpect(jsonPath("$.data.items[0].taskId").value(1001))
                .andExpect(jsonPath("$.data.items[0].subjectId").value(11));
    }

    @Test
    void foreignAndCrossOwnedRelationshipsNeverCreateARecord() throws Exception {
        for (int id : List.of(2001, 3001, 999999)) {
            create("{\"studyDate\":\"2026-11-14\",\"durationMinutes\":30,\"taskId\":" + id +
                    ",\"expectedPlanVersion\":1}", 403);
        }
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM STUDY_SESSIONS", Integer.class)).isZero();
    }

    @Test
    void versionAndDraftConflictsDoNotMutatePlansOrRecords() throws Exception {
        create("""
                {"studyDate":"2026-11-14","durationMinutes":30,"taskId":1001,"expectedPlanVersion":2}
                """, 409);
        create("""
                {"studyDate":"2026-11-14","durationMinutes":30,"taskId":1003,"expectedPlanVersion":4}
                """, 409);
        create("""
                {"studyDate":"2026-11-14","durationMinutes":30,"taskId":1001}
                """, 400);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM STUDY_SESSIONS", Integer.class)).isZero();
        assertThat(jdbc.queryForObject("SELECT status FROM STUDY_PLANS WHERE plan_id=103", String.class)).isEqualTo("DRAFT");
    }

    @Test
    void strictJsonAndUnsupportedSubjectOnlyWritesReturn400() throws Exception {
        for (String body : List.of(
                "{\"studyDate\":\"2026-11-14\",\"durationMinutes\":0}",
                "{\"studyDate\":\"2026-11-14\",\"durationMinutes\":-1}",
                "{\"studyDate\":\"2026-11-14\",\"durationMinutes\":1441}",
                "{\"studyDate\":\"2026-11-14\",\"durationMinutes\":1.5}",
                "{\"studyDate\":\"2026-11-14\",\"durationMinutes\":\"30\"}",
                "{\"studyDate\":\"2026-11-14\",\"durationMinutes\":true}",
                "{\"studyDate\":\"2026-11-31\",\"durationMinutes\":30}",
                "{\"studyDate\":\"2026-11-16\",\"durationMinutes\":30}",
                "{\"studyDate\":[2026,11,14],\"durationMinutes\":30}",
                "{\"studyDate\":\"2026-11-14\",\"durationMinutes\":30,\"subjectId\":11}",
                "{\"studyDate\":\"2026-11-14\",\"durationMinutes\":30,\"userId\":2}",
                "{\"studyDate\":\"2026-11-14\",\"durationMinutes\":null}",
                "{}")) create(body, 400);
        create("""
                {"studyDate":"2026-11-14","durationMinutes":30,"taskId":1001,
                 "expectedPlanVersion":3,"subjectId":12}
                """, 400);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM STUDY_SESSIONS", Integer.class)).isZero();
    }

    @Test
    void historyAndNullableSubjectAndUnlinkedTimeAreAllCountedOnce() throws Exception {
        record(1L, 1101L, "2026-11-14", 20);
        record(1L, 1001L, "2026-11-14", 30);
        record(1L, 1001L, "2026-11-14", 30);
        record(1L, 1002L, "2026-11-13", 15);
        record(1L, null, "2026-11-14", 10);
        record(2L, 2001L, "2026-11-14", 900);
        mvc.perform(get("/dashboard/study-stats").header("Authorization", "Bearer " + token)
                        .param("period", "CUSTOM").param("startDate", "2026-11-13")
                        .param("endDate", "2026-11-15"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.totalMinutes").value(105))
                .andExpect(jsonPath("$.data.dailyStudyMinutes[0].durationMinutes").value(15))
                .andExpect(jsonPath("$.data.dailyStudyMinutes[1].durationMinutes").value(90))
                .andExpect(jsonPath("$.data.dailyStudyMinutes[2].durationMinutes").value(0));
        mvc.perform(list(0, 20)).andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items", hasSize(5)));
    }

    @Test
    void paginationIsDeterministicWithTiedDatesAndEmptyLaterPages() throws Exception {
        for (int id=1001; id<=1006; id++) jdbc.update(
                "INSERT INTO STUDY_SESSIONS(session_id,user_id,study_date,actual_minutes,input_method) VALUES(?,1,'2026-11-14',1,'MANUAL')", id);
        mvc.perform(list(0, 3)).andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items[0].sessionId").value(1006))
                .andExpect(jsonPath("$.data.items[2].sessionId").value(1004))
                .andExpect(jsonPath("$.data.hasNext").value(true));
        mvc.perform(list(1, 3)).andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items[0].sessionId").value(1003))
                .andExpect(jsonPath("$.data.hasNext").value(false));
        mvc.perform(list(2, 3)).andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items", hasSize(0)));
    }

    @Test
    void periodLimitsAndKoreanDateBoundaryHaveExplicitResults() throws Exception {
        mvc.perform(get("/dashboard/study-stats").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.startDate").value("2026-11-09"))
                .andExpect(jsonPath("$.data.endDate").value("2026-11-15"))
                .andExpect(jsonPath("$.data.dailyStudyMinutes", hasSize(7)));
        mvc.perform(get("/dashboard/study-stats").header("Authorization", "Bearer " + token)
                        .param("period","LAST_30_DAYS"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.startDate").value("2026-10-17"))
                .andExpect(jsonPath("$.data.dailyStudyMinutes", hasSize(30)));
        mvc.perform(get("/dashboard/study-stats").header("Authorization", "Bearer " + token)
                        .param("period","CUSTOM").param("startDate","2024-02-28").param("endDate","2024-03-01"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.dailyStudyMinutes", hasSize(3)))
                .andExpect(jsonPath("$.data.dailyStudyMinutes[1].studyDate").value("2024-02-29"));
        for (String period : List.of("CUSTOM","invalid"))
            mvc.perform(get("/dashboard/study-stats").header("Authorization","Bearer "+token).param("period",period))
                    .andExpect(status().isBadRequest());
        mvc.perform(get("/dashboard/study-stats").header("Authorization","Bearer "+token)
                        .param("period","LAST_7_DAYS").param("startDate","2026-11-01"))
                .andExpect(status().isBadRequest());
        for (var request : List.of(list(-1,20),list(0,101),list(10001,20),
                get("/study/sessions").param("startDate","2026-11-15").param("endDate","2026-11-14"),
                get("/study/sessions").param("startDate","2024-01-01").param("endDate","2026-11-15")))
            mvc.perform(request.header("Authorization","Bearer "+token)).andExpect(status().isBadRequest());
    }

    @Test
    void authenticationAndCurrentMajorAreRequiredForEveryPersonalReadAndWrite() throws Exception {
        mvc.perform(get("/dashboard/study-stats")).andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.status").value("ERROR"));
        mvc.perform(get("/dashboard/study-stats").header("Authorization","Bearer not-a-token"))
                .andExpect(status().isUnauthorized());
        jdbc.update("UPDATE USERS SET major_type='NON_MAJOR' WHERE user_id=1");
        create("{\"studyDate\":\"2026-11-14\",\"durationMinutes\":30}",403);
        mvc.perform(list(0,20)).andExpect(status().isForbidden());
        mvc.perform(get("/dashboard/study-stats").header("Authorization","Bearer "+token))
                .andExpect(status().isForbidden());
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM STUDY_SESSIONS",Integer.class)).isZero();
    }

    @Test
    void invalidLegacyMinutesAndCorruptRelationshipsDoNotBecomeFakeStatistics() throws Exception {
        record(1L,null,"2026-11-14",null);
        mvc.perform(list(0,20)).andExpect(status().isServiceUnavailable());
        mvc.perform(get("/dashboard/study-stats").header("Authorization","Bearer "+token))
                .andExpect(status().isServiceUnavailable());
        jdbc.update("DELETE FROM STUDY_SESSIONS");
        record(1L,3001L,"2026-11-14",30);
        mvc.perform(list(0,20)).andExpect(status().isServiceUnavailable());
    }

    @Test
    void concurrentSavesCannotOverrunOneCalendarDay() throws Exception {
        try (var blocker=jdbc.getDataSource().getConnection();
             var executor=Executors.newFixedThreadPool(2)) {
            blocker.setAutoCommit(false);
            long connectionId;
            try(var statement=blocker.createStatement()) {
                try(var rs=statement.executeQuery("SELECT CONNECTION_ID()")) {
                    rs.next();connectionId=rs.getLong(1);
                }
                try(var rs=statement.executeQuery("SELECT user_id FROM USERS WHERE user_id=1 FOR UPDATE")) {
                    assertThat(rs.next()).isTrue();
                }
            }
            var first=executor.submit(()->create("{\"studyDate\":\"2026-11-14\",\"durationMinutes\":800}",-1)
                    .getResponse().getStatus());
            var second=executor.submit(()->create("{\"studyDate\":\"2026-11-14\",\"durationMinutes\":800}",-1)
                    .getResponse().getStatus());
            int waiting=0;
            try {
                long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(8);
                while(System.nanoTime()<deadline) {
                    waiting=jdbc.queryForObject("""
                            SELECT COUNT(*)
                            FROM information_schema.PROCESSLIST
                            WHERE COMMAND='Query'
                              AND INFO LIKE 'SELECT major_type FROM USERS WHERE user_id = %FOR UPDATE'
                            """,Integer.class);
                    if(waiting>=2) break;
                    Thread.sleep(25);
                }
                assertThat(waiting).as("both requests overlap while the user row is locked").isEqualTo(2);
            } finally {
                blocker.rollback();
            }
            assertThat(List.of(first.get(15,TimeUnit.SECONDS),second.get(15,TimeUnit.SECONDS)))
                    .containsExactlyInAnyOrder(200,409);
        }
        assertThat(jdbc.queryForObject(
                "SELECT SUM(actual_minutes) FROM STUDY_SESSIONS WHERE user_id=1",Long.class)).isEqualTo(800);
    }


    @Test
    void nullablePlanStatusIsAConflictInsteadOfAnUnexpectedError() throws Exception {
        jdbc.update("UPDATE STUDY_PLANS SET status=NULL WHERE plan_id=101");
        create("""
                {"studyDate":"2026-11-14","durationMinutes":30,"taskId":1001,"expectedPlanVersion":3}
                """,409);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM STUDY_SESSIONS",Integer.class)).isZero();
    }

    @Test
    void plannedManualRecordSupportsAnExistingTaskWithoutSubjectId() throws Exception {
        MvcResult result=create("""
                {"studyDate":"2026-11-14","durationMinutes":25,"taskId":1002,"expectedPlanVersion":3}
                """,200);
        JsonNode data=json.readTree(result.getResponse().getContentAsString()).get("data");
        assertThat(data.get("subjectId").isNull()).isTrue();
        assertThat(data.get("subjectName").asText()).isEqualTo("SAMPLE 임시 과목");
        assertThat(data.get("planId").asLong()).isEqualTo(101);
    }


    @Test
    void jdbcLocalDatesPreserveBothSidesOfTheLegacyCalendarCutover() throws Exception {
        MvcResult saved=create("{\"studyDate\":\"1582-10-10\",\"durationMinutes\":10}",200);
        long id=json.readTree(saved.getResponse().getContentAsString()).at("/data/sessionId").asLong();
        assertThat(jdbc.queryForObject("SELECT CAST(study_date AS CHAR) FROM STUDY_SESSIONS WHERE session_id=?",
                String.class,id)).isEqualTo("1582-10-10");
        create("{\"studyDate\":\"1582-10-20\",\"durationMinutes\":20}",200);
        mvc.perform(get("/study/sessions").header("Authorization","Bearer "+token)
                        .param("startDate","1582-10-10").param("endDate","1582-10-10"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.items",hasSize(1)))
                .andExpect(jsonPath("$.data.items[0].studyDate").value("1582-10-10"));
        mvc.perform(get("/dashboard/study-stats").header("Authorization","Bearer "+token)
                        .param("period","CUSTOM").param("startDate","1582-10-10").param("endDate","1582-10-20"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.totalMinutes").value(30))
                .andExpect(jsonPath("$.data.dailyStudyMinutes",hasSize(11)))
                .andExpect(jsonPath("$.data.dailyStudyMinutes[0].durationMinutes").value(10))
                .andExpect(jsonPath("$.data.dailyStudyMinutes[10].durationMinutes").value(20));
    }

    @Test
    void getDatesRejectOffsetsInsteadOfSilentlyDiscardingThem() throws Exception {
        mvc.perform(get("/study/sessions").header("Authorization","Bearer "+token)
                        .param("startDate","2026-11-14+09:00").param("endDate","2026-11-15"))
                .andExpect(status().isBadRequest());
        mvc.perform(get("/dashboard/study-stats").header("Authorization","Bearer "+token)
                        .param("period","CUSTOM").param("startDate","2026-11-14+09:00")
                        .param("endDate","2026-11-15")).andExpect(status().isBadRequest());
    }

    @Test
    void explicitlyEmptyQueryDatesCannotEvadePeriodConflicts() throws Exception {
        for (String field:List.of("startDate","endDate"))
            mvc.perform(get("/dashboard/study-stats").header("Authorization","Bearer "+token)
                            .param("period","LAST_7_DAYS").param(field,""))
                    .andExpect(status().isBadRequest());
    }

    @Test
    void patchChangesDateAndMinutesPreservingRecordAndPlanMetadata() throws Exception {
        record(1L,1101L,"2026-11-14",30);
        long id=jdbc.queryForObject("SELECT MAX(session_id) FROM STUDY_SESSIONS",Long.class);
        jdbc.update("UPDATE STUDY_SESSIONS SET digestion_level=3 WHERE session_id=?",id);
        edit(id,"2026-11-14",30,"2026-11-13",45,200)
                .andExpect(jsonPath("$.data.sessionId").value(id))
                .andExpect(jsonPath("$.data.studyDate").value("2026-11-13"))
                .andExpect(jsonPath("$.data.durationMinutes").value(45))
                .andExpect(jsonPath("$.data.taskId").value(1101))
                .andExpect(jsonPath("$.data.planId").value(102))
                .andExpect(jsonPath("$.data.subjectName").value("SAMPLE 과목"))
                .andExpect(jsonPath("$.data.inputMethod").value("MANUAL"));
        assertThat(jdbc.queryForObject("SELECT digestion_level FROM STUDY_SESSIONS WHERE session_id=?",Integer.class,id)).isEqualTo(3);
        assertThat(jdbc.queryForObject("SELECT status FROM STUDY_PLANS WHERE plan_id=102",String.class)).isEqualTo("REPLACED");
        assertThat(jdbc.queryForObject("SELECT estimated_minutes FROM STUDY_PLAN_DETAILS WHERE task_id=1101",Integer.class)).isEqualTo(60);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM STUDY_SESSIONS",Integer.class)).isEqualTo(1);
    }

    @Test
    void sameDayPatchSubtractsItsOwnOldMinutesBeforeDailyCap() throws Exception {
        record(1L,null,"2026-11-14",1400);
        long id=lastSession();
        edit(id,"2026-11-14",1400,"2026-11-14",1440,200);
        create("{\"studyDate\":\"2026-11-14\",\"durationMinutes\":1}",409);
        assertThat(jdbc.queryForObject("SELECT SUM(actual_minutes) FROM STUDY_SESSIONS",Long.class)).isEqualTo(1440);
    }

    @Test
    void movingIntoFullDayFailsWithoutChangingEitherDate() throws Exception {
        record(1L,null,"2026-11-14",100);long id=lastSession();
        record(1L,null,"2026-11-13",1400);
        edit(id,"2026-11-14",100,"2026-11-13",50,409);
        assertThat(jdbc.queryForObject("SELECT actual_minutes FROM STUDY_SESSIONS WHERE session_id=?",Integer.class,id)).isEqualTo(100);
        assertThat(jdbc.queryForObject("SELECT CAST(study_date AS CHAR) FROM STUDY_SESSIONS WHERE session_id=?",String.class,id)).isEqualTo("2026-11-14");
    }

    @Test
    void staleDateOrMinutesCannotOverwriteCurrentRecord() throws Exception {
        record(1L,null,"2026-11-14",30);long id=lastSession();
        edit(id,"2026-11-13",30,"2026-11-14",45,409);
        edit(id,"2026-11-14",29,"2026-11-14",45,409);
        assertThat(jdbc.queryForObject("SELECT actual_minutes FROM STUDY_SESSIONS WHERE session_id=?",Integer.class,id)).isEqualTo(30);
    }

    @Test
    void identicalPatchIsSuccessfulWithoutCreatingAnotherRecord() throws Exception {
        record(1L,null,"2026-11-14",30);long id=lastSession();
        edit(id,"2026-11-14",30,"2026-11-14",30,200);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM STUDY_SESSIONS",Integer.class)).isEqualTo(1);
    }

    @Test
    void patchRequiresAuthenticationCurrentMajorAndOwnership() throws Exception {
        record(1L,null,"2026-11-14",30);long id=lastSession();
        String body=editBody("2026-11-14",30,"2026-11-14",45);
        mvc.perform(patch("/study/sessions/"+id).contentType("application/json").content(body))
                .andExpect(status().isUnauthorized()).andExpect(jsonPath("$.status").value("ERROR"));
        String other=jwt.createToken(new JwtPrincipal(2L,"sample-two","SAMPLE",MajorType.NON_MAJOR,"USER"));
        mvc.perform(patch("/study/sessions/"+id).header("Authorization","Bearer "+other)
                .contentType("application/json").content(body)).andExpect(status().isForbidden());
        jdbc.update("UPDATE USERS SET major_type='NON_MAJOR' WHERE user_id=1");
        edit(id,"2026-11-14",30,"2026-11-14",45,403);
        assertThat(jdbc.queryForObject("SELECT actual_minutes FROM STUDY_SESSIONS WHERE session_id=?",Integer.class,id)).isEqualTo(30);
    }

    @Test
    void missingAndForeignSessionIdsHaveSameForbiddenResponse() throws Exception {
        record(2L,null,"2026-11-14",30);long foreign=lastSession();
        edit(foreign,"2026-11-14",30,"2026-11-14",45,403);
        edit(Long.MAX_VALUE,"2026-11-14",30,"2026-11-14",45,403);
    }

    @Test
    void patchRejectsWrongTypesUnknownFieldsFutureAndInvalidValues() throws Exception {
        record(1L,null,"2026-11-14",30);long id=lastSession();
        String good=editBody("2026-11-14",30,"2026-11-14",45);
        for(String body:List.of(
                good.replace("\"durationMinutes\":45","\"durationMinutes\":1.5"),
                good.replace("\"durationMinutes\":45","\"durationMinutes\":\"45\""),
                good.replace("\"durationMinutes\":45","\"durationMinutes\":0"),
                good.replace("\"durationMinutes\":45","\"durationMinutes\":1441"),
                good.replace("\"expectedDurationMinutes\":30","\"expectedDurationMinutes\":null"),
                good.replace("\"expectedDurationMinutes\":30","\"expectedDurationMinutes\":true"),
                good.replace("\"studyDate\":\"2026-11-14\"","\"studyDate\":\"2026-11-16\""),
                good.replace("\"studyDate\":\"2026-11-14\"","\"studyDate\":\"2026-02-30\""),
                good.replace("\"expectedStudyDate\":\"2026-11-14\"","\"expectedStudyDate\":\"2026-11-14+09:00\""),
                good.substring(0,good.length()-1)+",\"userId\":2}",
                good.substring(0,good.length()-1)+",\"taskId\":2001}",
                "{}")) {
            mvc.perform(patch("/study/sessions/"+id).header("Authorization","Bearer "+token)
                    .contentType("application/json").content(body)).andExpect(status().isBadRequest());
        }
        edit(0,"2026-11-14",30,"2026-11-14",45,400);
        assertThat(jdbc.queryForObject("SELECT actual_minutes FROM STUDY_SESSIONS WHERE session_id=?",Integer.class,id)).isEqualTo(30);
    }

    @Test
    void automaticRecordsAreNotRewrittenAsManualRecords() throws Exception {
        record(1L,null,"2026-11-14",30);long id=lastSession();
        jdbc.update("UPDATE STUDY_SESSIONS SET input_method='TIMER',start_time='08:00',end_time='08:30' WHERE session_id=?",id);
        edit(id,"2026-11-14",30,"2026-11-13",45,409);
        assertThat(jdbc.queryForObject("SELECT actual_minutes FROM STUDY_SESSIONS WHERE session_id=?",Integer.class,id)).isEqualTo(30);
        assertThat(jdbc.queryForObject("SELECT input_method FROM STUDY_SESSIONS WHERE session_id=?",String.class,id)).isEqualTo("TIMER");
    }

    @Test
    void invalidExistingLinkCannotBeChangedThroughPatch() throws Exception {
        record(1L,3001L,"2026-11-14",30);long id=lastSession();
        edit(id,"2026-11-14",30,"2026-11-13",45,503);
        assertThat(jdbc.queryForObject("SELECT task_id FROM STUDY_SESSIONS WHERE session_id=?",Long.class,id)).isEqualTo(3001);
    }

    @Test
    void patchMovesActualMinutesBetweenBothDailyTotals() throws Exception {
        record(1L,null,"2026-11-14",30);long id=lastSession();
        edit(id,"2026-11-14",30,"2026-11-13",45,200);
        mvc.perform(get("/dashboard/study-stats").header("Authorization","Bearer "+token)
                .param("period","CUSTOM").param("startDate","2026-11-13").param("endDate","2026-11-14"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.totalMinutes").value(45))
                .andExpect(jsonPath("$.data.dailyStudyMinutes[0].durationMinutes").value(45))
                .andExpect(jsonPath("$.data.dailyStudyMinutes[1].durationMinutes").value(0));
    }

    @Test
    void patchPreservesCalendarDatesAcrossGregorianCutover() throws Exception {
        var result=create("{\"studyDate\":\"1582-10-10\",\"durationMinutes\":10}",200);
        long id=json.readTree(result.getResponse().getContentAsString()).at("/data/sessionId").asLong();
        edit(id,"1582-10-10",10,"1582-10-20",20,200);
        assertThat(jdbc.queryForObject("SELECT CAST(study_date AS CHAR) FROM STUDY_SESSIONS WHERE session_id=?",String.class,id)).isEqualTo("1582-10-20");
    }

    @Test
    void concurrentEditsSerializeAndRejectStaleSnapshot() throws Exception {
        record(1L,null,"2026-11-14",25);long id=lastSession();
        try(var blocker=jdbc.getDataSource().getConnection();var executor=Executors.newFixedThreadPool(2)) {
            blocker.setAutoCommit(false);
            try(var statement=blocker.createStatement()) { statement.executeQuery("SELECT user_id FROM USERS WHERE user_id=1 FOR UPDATE"); }
            var first=executor.submit(()->edit(id,"2026-11-14",25,"2026-11-14",50,-1).andReturn().getResponse().getStatus());
            var second=executor.submit(()->edit(id,"2026-11-14",25,"2026-11-14",75,-1).andReturn().getResponse().getStatus());
            try { awaitTwoUserLocks(); } finally { blocker.rollback(); }
            assertThat(List.of(first.get(15,TimeUnit.SECONDS),second.get(15,TimeUnit.SECONDS))).containsExactlyInAnyOrder(200,409);
        }
        assertThat(jdbc.queryForObject("SELECT actual_minutes FROM STUDY_SESSIONS WHERE session_id=?",Integer.class,id)).isIn(50,75);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM STUDY_SESSIONS",Integer.class)).isEqualTo(1);
    }

    @Test
    void concurrentCreateAndEditShareDailyCapLock() throws Exception {
        record(1L,null,"2026-11-14",100);long id=lastSession();
        try(var blocker=jdbc.getDataSource().getConnection();var executor=Executors.newFixedThreadPool(2)) {
            blocker.setAutoCommit(false);
            try(var statement=blocker.createStatement()) { statement.executeQuery("SELECT user_id FROM USERS WHERE user_id=1 FOR UPDATE"); }
            var first=executor.submit(()->edit(id,"2026-11-14",100,"2026-11-14",800,-1).andReturn().getResponse().getStatus());
            var second=executor.submit(()->create("{\"studyDate\":\"2026-11-14\",\"durationMinutes\":700}",-1).getResponse().getStatus());
            try { awaitTwoUserLocks(); } finally { blocker.rollback(); }
            assertThat(List.of(first.get(15,TimeUnit.SECONDS),second.get(15,TimeUnit.SECONDS))).containsExactlyInAnyOrder(200,409);
        }
        assertThat(jdbc.queryForObject("SELECT SUM(actual_minutes) FROM STUDY_SESSIONS WHERE user_id=1",Long.class)).isEqualTo(800);
    }

    private void awaitTwoUserLocks() throws Exception {
        int waiting=0;long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(8);
        while(System.nanoTime()<deadline) {
            waiting=jdbc.queryForObject("SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE COMMAND='Query' AND INFO LIKE 'SELECT major_type FROM USERS WHERE user_id = %FOR UPDATE'",Integer.class);
            if(waiting>=2)break;
            Thread.sleep(25);
        }
        assertThat(waiting).as("both requests wait on the user lock").isEqualTo(2);
    }
    private long lastSession() { return jdbc.queryForObject("SELECT MAX(session_id) FROM STUDY_SESSIONS",Long.class); }
    private String editBody(String expectedDate,int expectedMinutes,String date,int minutes) {
        return "{\"studyDate\":\""+date+"\",\"durationMinutes\":"+minutes+
                ",\"expectedStudyDate\":\""+expectedDate+"\",\"expectedDurationMinutes\":"+expectedMinutes+"}";
    }
    private org.springframework.test.web.servlet.ResultActions edit(long id,String expectedDate,int expectedMinutes,String date,int minutes,int expectedStatus) throws Exception {
        var action=mvc.perform(patch("/study/sessions/"+id).header("Authorization","Bearer "+token)
                .contentType("application/json").content(editBody(expectedDate,expectedMinutes,date,minutes)));
        if(expectedStatus!=-1)action.andExpect(status().is(expectedStatus));
        return action;
    }

    @Test
    void deleteRemovesOnlyOwnedRecordAndUpdatesStats() throws Exception {
        record(1L,1101L,"2026-11-14",30);long id=lastSession();
        record(1L,null,"2026-11-14",20);
        remove(id,"2026-11-14",30,1101L,200)
                .andExpect(jsonPath("$.data.sessionId").value(id)).andExpect(jsonPath("$.data.deleted").value(true));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM STUDY_SESSIONS WHERE session_id=?",Integer.class,id)).isZero();
        assertThat(jdbc.queryForObject("SELECT actual_minutes FROM STUDY_SESSIONS",Integer.class)).isEqualTo(20);
        assertThat(jdbc.queryForObject("SELECT estimated_minutes FROM STUDY_PLAN_DETAILS WHERE task_id=1101",Integer.class)).isEqualTo(60);
        assertThat(jdbc.queryForObject("SELECT status FROM STUDY_PLANS WHERE plan_id=102",String.class)).isEqualTo("REPLACED");
        mvc.perform(get("/dashboard/study-stats").header("Authorization","Bearer "+token)
                .param("period","CUSTOM").param("startDate","2026-11-14").param("endDate","2026-11-14"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.totalMinutes").value(20));
    }

    @Test
    void deleteChecksOriginalLinkAsWellAsDateAndMinutes() throws Exception {
        record(1L,1001L,"2026-11-14",30);long id=lastSession();
        remove(id,"2026-11-14",30,null,409);
        remove(id,"2026-11-13",30,1001L,409);
        remove(id,"2026-11-14",29,1001L,409);
        assertThat(jdbc.queryForObject("SELECT task_id FROM STUDY_SESSIONS WHERE session_id=?",Long.class,id)).isEqualTo(1001L);
    }

    @Test
    void deleteRequiresAuthenticationCurrentMajorAndOwnership() throws Exception {
        record(2L,null,"2026-11-14",30);long id=lastSession();
        remove(id,"2026-11-14",30,null,403);
        remove(Long.MAX_VALUE,"2026-11-14",30,null,403);
        mvc.perform(delete("/study/sessions/"+id).contentType("application/json").content(deleteBody("2026-11-14",30,null)))
                .andExpect(status().isUnauthorized());
        record(1L,null,"2026-11-14",30);long own=lastSession();
        jdbc.update("UPDATE USERS SET major_type='NON_MAJOR' WHERE user_id=1");
        remove(own,"2026-11-14",30,null,403);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM STUDY_SESSIONS",Integer.class)).isEqualTo(2);
    }

    @Test
    void deleteRejectsInvalidSnapshotAndKeepsAutomaticRecords() throws Exception {
        record(1L,null,"2026-11-14",30);long id=lastSession();
        for(String body:List.of("{}",deleteBody("2026-02-30",30,null),
                deleteBody("2026-11-14",0,null),deleteBody("2026-11-14",1441,null),
                deleteBody("2026-11-14",30,-1L),
                deleteBody("2026-11-14",30,null).replace("30","1.5"),
                deleteBody("2026-11-14",30,null).replace("30","\"30\""),
                "{\"expectedStudyDate\":\"2026-11-14\",\"expectedDurationMinutes\":30,\"userId\":2}")) {
            mvc.perform(delete("/study/sessions/"+id).header("Authorization","Bearer "+token)
                .contentType("application/json").content(body)).andExpect(status().isBadRequest());
        }
        jdbc.update("UPDATE STUDY_SESSIONS SET input_method='TIMER' WHERE session_id=?",id);
        remove(id,"2026-11-14",30,null,409);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM STUDY_SESSIONS",Integer.class)).isEqualTo(1);
    }

    @Test
    void repeatedDeleteCannotAffectAnyOtherRecord() throws Exception {
        record(1L,null,"2026-11-14",30);long id=lastSession();
        remove(id,"2026-11-14",30,null,200);
        record(1L,null,"2026-11-14",30);long other=lastSession();
        remove(id,"2026-11-14",30,null,403);
        assertThat(jdbc.queryForObject("SELECT session_id FROM STUDY_SESSIONS",Long.class)).isEqualTo(other);
    }

    @Test
    void planTaskChoicesExposeRealOwnedIdentifiers() throws Exception {
        mvc.perform(get("/study/plan-tasks").header("Authorization","Bearer "+token).param("date","2026-11-13"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.items",hasSize(1)))
                .andExpect(jsonPath("$.data.items[0].taskId").value(1002))
                .andExpect(jsonPath("$.data.items[0].planId").value(101))
                .andExpect(jsonPath("$.data.items[0].planVersion").value(3))
                .andExpect(jsonPath("$.data.items[0].subjectId").value(nullValue()))
                .andExpect(jsonPath("$.data.items[0].subjectName").value("SAMPLE 임시 과목"));
        mvc.perform(get("/study/plan-tasks").header("Authorization","Bearer "+token))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.items",hasSize(2)));
        mvc.perform(get("/study/plan-tasks").header("Authorization","Bearer "+token).param("includeReplaced","true"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.items",hasSize(3)));
    }

    @Test
    void choicesRespectAuthenticationMajorPaginationAndValidDates() throws Exception {
        mvc.perform(get("/study/plan-tasks")).andExpect(status().isUnauthorized());
        for(String date:List.of("2026-02-30","2026-11-14+09:00",""))
            mvc.perform(get("/study/plan-tasks").header("Authorization","Bearer "+token).param("date",date))
                    .andExpect(status().isBadRequest());
        mvc.perform(get("/study/plan-tasks").header("Authorization","Bearer "+token).param("pageSize","1"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.items",hasSize(1)))
                .andExpect(jsonPath("$.data.hasNext").value(true));
        mvc.perform(get("/study/plan-tasks").header("Authorization","Bearer "+token).param("pageSize","1").param("page","1"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.items",hasSize(1)))
                .andExpect(jsonPath("$.data.hasNext").value(false));
        mvc.perform(get("/study/plan-tasks").header("Authorization","Bearer "+token).param("pageSize","101"))
                .andExpect(status().isBadRequest());
        jdbc.update("UPDATE USERS SET major_type='NON_MAJOR' WHERE user_id=1");
        mvc.perform(get("/study/plan-tasks").header("Authorization","Bearer "+token)).andExpect(status().isForbidden());
    }

    @Test
    void patchCanConnectAnExistingUnlinkedRecordAndDisconnectIt() throws Exception {
        record(1L,null,"2026-11-14",30);long id=lastSession();
        linkedEdit(id,null,1002L,3,200).andExpect(jsonPath("$.data.taskId").value(1002))
                .andExpect(jsonPath("$.data.subjectId").value(nullValue()))
                .andExpect(jsonPath("$.data.subjectName").value("SAMPLE 임시 과목"));
        linkedEdit(id,1002L,null,null,200).andExpect(jsonPath("$.data.taskId").value(nullValue()))
                .andExpect(jsonPath("$.data.subjectName").value(nullValue()));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM STUDY_SESSIONS",Integer.class)).isEqualTo(1);
    }

    @Test
    void linkingRejectsForeignDraftStaleVersionAndStaleOriginalLink() throws Exception {
        record(1L,null,"2026-11-14",30);long id=lastSession();
        linkedEdit(id,null,2001L,1,403);
        linkedEdit(id,null,1003L,4,409);
        linkedEdit(id,null,1001L,2,409);
        linkedEdit(id,null,1001L,null,400);
        linkedEdit(id,null,1001L,3,200);
        linkedEdit(id,null,1002L,3,409);
        assertThat(jdbc.queryForObject("SELECT task_id FROM STUDY_SESSIONS WHERE session_id=?",Long.class,id)).isEqualTo(1001);
    }

    @Test
    void relinkingPreservesOldClientDateOnlyPatchCompatibility() throws Exception {
        record(1L,1001L,"2026-11-14",30);long id=lastSession();
        edit(id,"2026-11-14",30,"2026-11-13",45,200).andExpect(jsonPath("$.data.taskId").value(1001));
        assertThat(jdbc.queryForObject("SELECT estimated_minutes FROM STUDY_PLAN_DETAILS WHERE task_id=1001",Integer.class)).isEqualTo(60);
    }

    @Test
    void staleDeleteAfterLinkOnlyChangeDoesNotRemoveRecord() throws Exception {
        record(1L,null,"2026-11-14",30);long id=lastSession();
        linkedEdit(id,null,1001L,3,200);
        remove(id,"2026-11-14",30,null,409);
        remove(id,"2026-11-14",30,1001L,200);
    }

    @Test
    void deleteAndRelinkSerializeAgainstSameSnapshot() throws Exception {
        record(1L,null,"2026-11-14",30);long id=lastSession();
        try(var blocker=jdbc.getDataSource().getConnection();var executor=Executors.newFixedThreadPool(2)) {
            blocker.setAutoCommit(false);
            try(var statement=blocker.createStatement()){statement.executeQuery("SELECT user_id FROM USERS WHERE user_id=1 FOR UPDATE");}
            var first=executor.submit(()->remove(id,"2026-11-14",30,null,-1).andReturn().getResponse().getStatus());
            var second=executor.submit(()->linkedEdit(id,null,1001L,3,-1).andReturn().getResponse().getStatus());
            try{awaitTwoUserLocks();}finally{blocker.rollback();}
            var statuses=List.of(first.get(15,TimeUnit.SECONDS),second.get(15,TimeUnit.SECONDS));
            assertThat(statuses.stream().filter(s->s==200).count()).isEqualTo(1);
            assertThat(statuses).allMatch(s->s==200||s==403||s==409);
        }
    }

    @Test
    void newDateOnlyClientAlsoDetectsConcurrentLinkOnlyChange() throws Exception {
        record(1L,null,"2026-11-14",30);long id=lastSession();
        linkedEdit(id,null,1001L,3,200);
        String original=editBody("2026-11-14",30,"2026-11-14",45);
        mvc.perform(patch("/study/sessions/"+id).header("Authorization","Bearer "+token)
                .contentType("application/json").content(original.substring(0,original.length()-1)+",\"expectedTask\":{\"taskId\":null}}"))
                .andExpect(status().isConflict());
        assertThat(jdbc.queryForObject("SELECT actual_minutes FROM STUDY_SESSIONS WHERE session_id=?",Integer.class,id)).isEqualTo(30);
    }

    private String deleteBody(String date,int minutes,Long task) {
        return "{\"expectedStudyDate\":\""+date+"\",\"expectedDurationMinutes\":"+minutes+",\"expectedTaskId\":"+task+"}";
    }
    private org.springframework.test.web.servlet.ResultActions remove(long id,String date,int minutes,Long task,int expected) throws Exception {
        var result=mvc.perform(delete("/study/sessions/"+id).header("Authorization","Bearer "+token)
                .contentType("application/json").content(deleteBody(date,minutes,task)));
        if(expected!=-1)result.andExpect(status().is(expected));return result;
    }
    private org.springframework.test.web.servlet.ResultActions linkedEdit(long id,Long previous,Long desired,Integer version,int expected) throws Exception {
        String original=editBody("2026-11-14",30,"2026-11-14",30);
        String body=original.substring(0,original.length()-1)+",\"taskLink\":{\"taskId\":"+desired+
                ",\"expectedTaskId\":"+previous+",\"expectedPlanVersion\":"+version+"}}";
        var result=mvc.perform(patch("/study/sessions/"+id).header("Authorization","Bearer "+token)
                .contentType("application/json").content(body));
        if(expected!=-1)result.andExpect(status().is(expected));return result;
    }

    private org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder list(int page,int size) {
        return get("/study/sessions").header("Authorization","Bearer "+token)
                .param("startDate","2026-11-13").param("endDate","2026-11-15")
                .param("page",String.valueOf(page)).param("pageSize",String.valueOf(size));
    }
    private MvcResult create(String body,int expected) throws Exception {
        var action=mvc.perform(post("/study/sessions").header("Authorization","Bearer "+token)
                .contentType("application/json").content(body));
        if(expected!=-1) action.andExpect(status().is(expected));
        return action.andReturn();
    }
    private void record(Long user,Long task,String date,Integer minutes) {
        jdbc.update("INSERT INTO STUDY_SESSIONS(user_id,task_id,study_date,actual_minutes,input_method) VALUES(?,?,?,?, 'MANUAL')",
                user,task,java.sql.Date.valueOf(date),minutes);
    }
}
