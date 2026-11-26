package com.passpace.user.withdrawal;

import com.passpace.constant.MajorType;
import com.passpace.error.ErrorCode;
import com.passpace.error.exception.UserException;
import com.passpace.jwt.JwtPrincipal;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.support.TransactionTemplate;

import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

/** Only a separately prepared SAMPLE database is permitted; never uses application datasource settings. */
@EnabledIfEnvironmentVariable(named = "PASSPACE_WITHDRAWAL_DB_TEST", matches = "isolated-only")
class AccountWithdrawalDatabaseTest {
    private JdbcTemplate jdbc;
    private TransactionTemplate transaction;
    private AccountWithdrawalService service;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(4);
    private static final String PASSWORD = "SAMPLE_password";
    private record Account(long id, String loginId, long goal, long plan, long task, long conversation) { }

    @BeforeEach void connectOnlyToExplicitSampleDatabase() {
        String url = System.getenv("PASSPACE_WITHDRAWAL_TEST_JDBC");
        assertNotNull(url);
        assertTrue(url.matches("jdbc:mariadb://127\\.0\\.0\\.1:[0-9]+/withdrawal_sample"));
        int port = Integer.parseInt(url.split(":")[3].split("/")[0]);
        assertFalse(java.util.Set.of(3306,3308,8080,18080).contains(port));
        var source = new DriverManagerDataSource(url, "root", "");
        jdbc = new JdbcTemplate(source);
        assertEquals("withdrawal_sample", jdbc.queryForObject("SELECT DATABASE()", String.class));
        Path actual = Path.of(jdbc.queryForObject("SELECT @@datadir", String.class)).toAbsolutePath().normalize();
        Path expected = Path.of(System.getenv("PASSPACE_WITHDRAWAL_TEST_DIRECTORY")).toAbsolutePath().normalize();
        assertEquals(expected, actual);
        assertEquals("database", expected.getFileName().toString());
        assertEquals("isolated", expected.getParent().getFileName().toString());
        assertTrue(expected.getParent().getParent().getFileName().toString().startsWith("withdrawal-hard-delete-"));
        transaction = new TransactionTemplate(new DataSourceTransactionManager(source));
        service = new AccountWithdrawalService(new AccountWithdrawalRepository(jdbc), encoder);
    }

    private Account account(String label) {
        String login = "SAMPLE_" + label + "_" + UUID.randomUUID().toString().substring(0,8);
        jdbc.update("INSERT INTO USERS(login_id,email,password_hash,nickname,major_type,role) VALUES(?,?,?,?,?,?)",
                login, login + "@example.invalid", encoder.encode(PASSWORD), "SAMPLE", "MAJOR", "USER");
        long id = jdbc.queryForObject("SELECT user_id FROM USERS WHERE login_id=?", Long.class, login);
        jdbc.update("INSERT INTO USER_GOALS(user_id,certification_id,goal_title,status) VALUES(?,1,'SAMPLE','ACTIVE')", id);
        long goal = jdbc.queryForObject("SELECT goal_id FROM USER_GOALS WHERE user_id=?", Long.class, id);
        jdbc.update("INSERT INTO GOAL_SUBJECTS(goal_id,certification_subject_id,familiarity_level) VALUES(?,11,1)", goal);
        jdbc.update("INSERT INTO STUDY_PLANS(user_id,plan_name,version_no,start_date,end_date,status) VALUES(?,'SAMPLE',1,CURRENT_DATE(),DATE_ADD(CURRENT_DATE(),INTERVAL 7 DAY),'ACTIVE')",id);
        long plan = jdbc.queryForObject("SELECT plan_id FROM STUDY_PLANS WHERE user_id=?", Long.class,id);
        jdbc.update("INSERT INTO PLAN_GOALS(plan_id,goal_id) VALUES(?,?)",plan,goal);
        jdbc.update("INSERT INTO STUDY_PLAN_DETAILS(user_id,plan_id,goal_id,certification_subject_id,subject_name,scheduled_date,estimated_minutes) VALUES(?,?,?,11,'SAMPLE',CURRENT_DATE(),60)",id,plan,goal);
        long task=jdbc.queryForObject("SELECT task_id FROM STUDY_PLAN_DETAILS WHERE user_id=?",Long.class,id);
        jdbc.update("INSERT INTO STUDY_SESSIONS(user_id,task_id,study_date,actual_minutes,input_method) VALUES(?,?,CURRENT_DATE(),30,'MANUAL')",id,task);
        jdbc.update("INSERT INTO CHAT_CONVERSATIONS(user_id,title,status) VALUES(?,'SAMPLE','ACTIVE')",id);
        long conversation=jdbc.queryForObject("SELECT con_id FROM CHAT_CONVERSATIONS WHERE user_id=?",Long.class,id);
        jdbc.update("INSERT INTO CHAT_MESSAGES(con_id,role,content) VALUES(?,'USER','SAMPLE')",conversation);
        long message=jdbc.queryForObject("SELECT message_id FROM CHAT_MESSAGES WHERE con_id=?",Long.class,conversation);
        jdbc.update("INSERT INTO AI_PLAN_PROPOSALS(user_id,goal_id,current_plan_id,proposed_plan_id,message_id,model_name) VALUES(?,?,?,?,?,'SAMPLE')",id,goal,plan,plan,message);
        return new Account(id,login,goal,plan,task,conversation);
    }

    private Map<String,String> scopes(Account a) {
        Map<String,String> result = new LinkedHashMap<>();
        result.put("USERS","user_id="+a.id);
        result.put("USER_GOALS","user_id="+a.id);
        result.put("GOAL_SUBJECTS","goal_id="+a.goal);
        result.put("STUDY_PLANS","user_id="+a.id);
        result.put("PLAN_GOALS","plan_id="+a.plan+" OR goal_id="+a.goal);
        result.put("STUDY_PLAN_DETAILS","user_id="+a.id);
        result.put("STUDY_SESSIONS","user_id="+a.id);
        result.put("CHAT_CONVERSATIONS","user_id="+a.id);
        result.put("CHAT_MESSAGES","con_id="+a.conversation);
        result.put("AI_PLAN_PROPOSALS","user_id="+a.id);
        return result;
    }

    private Map<String,Object> snapshot(Account a) {
        Map<String,Object> result=new LinkedHashMap<>();
        scopes(a).forEach((table,where)->result.put(table,jdbc.queryForList("SELECT * FROM "+table+" WHERE "+where+" ORDER BY 1")));
        return result;
    }

    private void withdraw(Account a) {
        var principal=new JwtPrincipal(a.id,a.loginId,"SAMPLE", MajorType.MAJOR,"USER");
        transaction.executeWithoutResult(ignored -> service.withdraw(principal,
                new WithdrawalDtos.Request(PASSWORD,a.loginId+"회원탈퇴",true)));
    }

    @Test void deletesWholeOwnedGraphWhileOtherMemberAndPublicCatalogStayUnchanged() {
        Account owner=account("DELETE"), other=account("OTHER");
        var otherBefore=snapshot(other);
        var catalog=jdbc.queryForList("SELECT * FROM CERTIFICATION_SUBJECTS ORDER BY 1");
        withdraw(owner);
        scopes(owner).forEach((table,where)->assertEquals(0L,jdbc.queryForObject("SELECT COUNT(*) FROM "+table+" WHERE "+where,Long.class),table));
        assertTrue(otherBefore.equals(snapshot(other)),"Other member graph must be unchanged");
        assertTrue(catalog.equals(jdbc.queryForList("SELECT * FROM CERTIFICATION_SUBJECTS ORDER BY 1")),"Public catalog must be unchanged");
    }

    @Test void failureAtFinalUserDeleteRollsBackAllEarlierChildDeletes() {
        Account owner=account("ROLLBACK"),other=account("SAFE");
        var before=snapshot(owner);var otherBefore=snapshot(other);
        String trigger="SAMPLE_STOP_"+owner.id;
        jdbc.execute("CREATE TRIGGER "+trigger+" BEFORE DELETE ON USERS FOR EACH ROW BEGIN IF OLD.user_id="+owner.id+" THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='SAMPLE deletion failure'; END IF; END");
        assertThrows(UserException.class,()->withdraw(owner));
        assertTrue(before.equals(snapshot(owner)),"Any late failure must restore the entire member graph");
        assertTrue(otherBefore.equals(snapshot(other)),"Other member graph must be unchanged");
    }

    @Test void foreignMembersReferenceIsNeverDeletedToForceWithdrawal() {
        Account owner=account("CROSS"),other=account("FOREIGN");
        jdbc.update("INSERT INTO STUDY_SESSIONS(user_id,task_id,study_date,actual_minutes,input_method) VALUES(?,?,CURRENT_DATE(),5,'MANUAL')",other.id,owner.task);
        var before=snapshot(owner);var otherBefore=snapshot(other);
        var error=assertThrows(UserException.class,()->withdraw(owner));
        assertEquals(ErrorCode.DATA_INTEGRITY_VIOLATION,error.getErrorCode());
        assertTrue(before.equals(snapshot(owner)),"Inconsistent ownership must roll back all deletion");
        assertTrue(otherBefore.equals(snapshot(other)),"Never erase the other member's reference");
    }
}
