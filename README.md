# 패스페이스(PASS PACE)

## 1. 담당과 폴더

```
src/main/java/com/passpace/          ← 12주차 강의안(ExCode) 형식: 기능별이 아니라 "역할별" 폴더
├─ PasspaceApplication.java      실행 시작점
├─ config/      SecurityConfig(권한 규칙) · SwaggerConfig · JacksonConfig
├─ jwt/         JwtUtil · JwtFilter 등 토큰 만들기·검사 9개 (강의안 그대로)
├─ constant/    ResponseStatus · Role · 코드값 Enum · CollectSources
├─ controller/  Auth · User · Page · Home · ChatApi · MultiGoalPlanner · CollectAdmin
├─ domain/      공통 계약 record (UserStudyProfile 등)
├─ dto/         ResponseDto + auth/ · user/ · chat/ · collect/
├─ error/       ErrorCode · ErrorResponseDto · GlobalExceptionHandler · exception/
├─ repository/  DB 접근 (JdbcTemplate)
├─ service/     업무 규칙 (AuthService 등)
├─ client/      외부 API·페이지 가져오기 (Claude API, 공공데이터, 후기 페이지)
├─ crawler/     후기 탐색·URL 장부
└─ util/        ResponseUtil
src/main/resources/
├─ static/js/auth.js                 [JWT] 토큰 저장·API 호출·헤더 표시 (모든 화면 공통)
├─ templates/fragments/layout.html   [한결] 공통 헤더·푸터
├─ templates/fragments/chatbot.html  [동건] 챗봇 위젯 (모든 페이지 하단에 들어감)
├─ templates/{home, user/*}          [한결]
├─ templates/collect/admin.html      [용성] 수집 실행 화면
├─ prompts/                          [동건] LLM 지시문
└─ collect/                          [용성] 후기 탐색 목록·직접 지정 URL, 샘플 시험일정
db/  01_schema(= passpace_erd.sql) → 02_schema_ext → 03_seed (04 는 더미 삭제) → 08_add_user_role (JWT 권한 칸)
     → 09_review_sources (컴활·ADsP) → 10_review_subject_mentions (과목 언급) → 11_provisional_subject_ratio (과목 비율)
```

| 담당 | 화면·주소 | 쓰는 테이블 | 읽는 테이블 |
|---|---|---|---|
| 한결 | `/`, `/login`, `/signup`, `/mypage` + API `/auth/**`, `/users/me/**` | USERS, USER_GOALS, GOAL_SUBJECTS | EXAM_ROUNDS, CERTIFICATION_SUBJECTS |
| 용성 | `/admin/collect` (POST `/admin/collect/exam`, `/admin/collect/reviews`, `/reviews/discover`, `/reviews/preview?url=`, `/reference-stats`) | DATA_SYNC_JOBS, EXAM_ROUNDS, EXAM_SCHEDULE_CHANGE_LOGS, PASS_REVIEWS | CERTIFICATIONS |
| 동건 | 챗봇 위젯, POST `/api/chat` | CHAT_CONVERSATIONS, CHAT_MESSAGES | PASS_REVIEWS(계약 경유), EXAM_ROUNDS, CERTIFICATION_SUBJECTS |

## 2. 세 영역이 만나는 곳 (합칠 때 확인할 곳은 여기뿐)

세 영역은 서로의 클래스를 import 하지 않는다. 연결은 아래 세 가지뿐이다.

| 연결점 | 만드는 쪽 | 쓰는 쪽 | 내용 |
|---|---|---|---|
| JWT 토큰 → `JwtPrincipal` (userId·loginId·nickname·majorType·role) | `AuthService.login` (POST /auth/login) | 동건(챗봇·전공), 한결(마이페이지), 용성(ADMIN 권한) | Controller 에서 `@AuthenticationPrincipal JwtPrincipal loginUser` 로 꺼낸다. **세션은 쓰지 않는다** |
| 화면의 로그인 상태 | `static/js/auth.js` (`window.PP`) | 모든 화면(헤더·챗봇 위젯·마이페이지·관리자) | 서버는 누가 보는지 모른다. JS 가 토큰을 보고 `data-pp-when="guest/member/admin"` 요소를 보이거나 숨긴다 |
| `UserStudyProfileQuery` | 한결 `repository.JdbcUserStudyProfileQuery` | 동건 | 마이페이지의 목표 시험일·하루 시간·과목별 이해도 |
| `ReviewStatsQuery` | 용성 `repository.JdbcReviewStatsQuery` | 동건 | 조건에 맞는 VALID 후기 목록 |
| `ReviewExtractor` | 용성 `service.RuleBasedReviewExtractor` | 용성(수집 서비스) | 나중에 동건의 LLM 추출기로 교체 가능 |
| 화면 `fragments/chatbot :: widget` | 동건 | 한결(모든 페이지 하단), 용성(관리 화면) | CSS·id 는 `pp-chat-` 접두어 |
| DB 테이블 | 표 1 참고 | | 테이블마다 쓰는 사람은 한 명 |

## 2-1. 로그인 방식: JWT (12주차 강의안 기준)

세션 방식(서버가 로그인 상태를 기억)을 없애고 **토큰 방식**으로 바꿨다. 나중에 앱(Flutter)을 만들어도 서버를 그대로 쓰기 위해서다.

```
[웹 화면 JS / 앱] ── POST /auth/login ──────────────→ 토큰(accessToken) 받기 → 저장
                 ── Authorization: Bearer 토큰 ───→ JwtFilter 가 검사 → Controller
```

| 주소 | 누가 | 설명 |
|---|---|---|
| `POST /auth/signup` · `POST /auth/login` | 누구나 | 가입 · 토큰 발급 |
| `GET /auth/user-info` | 로그인 | 내 정보 (헤더 "닉네임 님") |
| `PUT /users/me` · `GET/PUT /users/me/goal` | 로그인 | 마이페이지. 회원정보를 바꾸면 **새 토큰**을 돌려준다 |
| `/api/chat/**` | 로그인 | 챗봇·통합 학습계획 |
| `/admin/collect/**` (API) | ADMIN | 수집 관리. 화면 껍데기 `GET /admin/collect` 만 열려 있다 |
| `/`, `/login`, `/signup`, `/mypage`, `/admin/collect`, css·js | 누구나 | HTML 껍데기. 내용은 JS 가 토큰으로 API 를 불러 채운다 |

- 응답은 항상 `{"status":"SUCCESS|ERROR","code":200,"data":...}`. 실패 이유는 `error/ErrorCode` 한 곳에 모여 있다
- 권한 규칙은 `config/SecurityConfig` 한 곳, 토큰 없이 열리는 주소는 `jwt/SecurityPaths` 한 곳에서만 고친다
- 로그아웃 = 브라우저에 저장된 토큰 지우기 (서버 API 없음). 토큰 유효시간 24시간
- Swagger: http://localhost:8080/swagger-ui.html → `/auth/login` 실행 → 받은 토큰을 오른쪽 위 **Authorize** 에 넣기
- 서명 열쇠 `jwt.secret` 은 개발용 기본값만 `application.yml` 에 있다. 실제 값은 환경변수 `JWT_SECRET` (저장소에 올리지 않음)
- IntelliJ: Lombok 을 쓰므로 `Settings > Annotation Processors > Enable annotation processing` 체크

## 3. 실행 순서

### 3-1. 준비물
- JDK 21, IntelliJ, MariaDB 10.11 이상, DBeaver
- (챗봇) Claude API 키 — 없어도 앱은 실행되고 챗봇은 "기본 안내"로 답한다. 7장 참고 (예전 로컬 LLM Ollama 는 쓰지 않는다)

### 3-2. DB (DBeaver, root 계정)
```sql
CREATE USER IF NOT EXISTS 'passpace'@'localhost' IDENTIFIED BY 'passpace';
GRANT ALL ON passpace_merged.* TO 'passpace'@'localhost';
```
그다음 `db/01_schema.sql` → `db/02_schema_ext.sql` → `db/03_seed.sql` → `db/08_add_user_role.sql` → `db/09_review_sources.sql` → `db/10_review_subject_mentions.sql` → `db/11_provisional_subject_ratio.sql` 을 차례로 열고 **스크립트 실행(Alt+X)**.
- 09 는 컴활 1급·ADsP 자격증·과목 행, 10 은 후기별 과목 언급 테이블(REVIEW_SUBJECT_MENTIONS), 11 은 ADsP·컴활 과목 비율 8줄이다 (6-1장). 셋 다 여러 번 실행해도 안전하다
- 08 은 JWT 권한(`USERS.role`) 칸을 만든다. 관리자 화면을 쓰려면 08 파일 맨 아래 `UPDATE ... role = 'ADMIN'` 줄에 내 아이디를 넣어 따로 실행하고 **다시 로그인**
- `01_schema.sql` 은 팀 기준 `passpace_erd.sql` 과 같은 내용이다. 이미 passpace_erd.sql 을 실행했다면 01 은 건너뛰고 02, 03 만 실행
- 01 실행 결과 `table_count 20`, 03 실행 결과 `dummy_reviews 48` 이면 성공
- 01 을 다시 실행하면 모든 테이블이 지워지고 새로 만들어진다 (그 뒤 02, 03 도 다시)

### 3-3. 설정
`src/main/resources/application-local.yml.example` 을 같은 폴더에 `application-local.yml` 로 복사하고 DB 비밀번호·API 키·모델명을 적는다. (공유 금지)
- 공공데이터 인증키가 없으면 시험일정은 **샘플(실제 일정 아님)** 로 저장된다

### 3-4. 실행
IntelliJ 에서 `PasspaceApplication` 실행 → http://localhost:8080
1. `/admin/collect` → **시험일정 수집 실행** (메인 화면에 일정 카드가 생김)
2. `/signup` 회원가입 → `/mypage` 에서 목표 회차·하루 시간·과목별 이해도 저장
3. 오른쪽 아래 💬 → "비전공자가 정보처리기사 필기 준비중이다. 시험날은 3월 20일, 하루 2.5시간. 학습계획 세워줄 수 있는지?"

### 3-5. 혼자 개발할 때 (fake 프로필)
IntelliJ 실행 설정 → Active profiles 에 `fake` → 용성의 후기 SQL 대신 동건의 가짜 후기(12건)로 챗봇이 동작한다.

## 4. 챗봇 처리 흐름 (동건)
```
비로그인 → 위젯은 "로그인 후 이용" 안내만, /api/chat 은 401
로그인 질문 → ⓪ 대화방 준비 + 같은 대화방의 앞 질문(최근 5개) 읽기 → 질문 저장
     → 학습 계획 질문이 아니면 안내만 (과목을 물으면 DB 과목 목록), 계산·LLM 없음
     → ① 조건 추출: 이번 질문 정규식 → 앞 질문 정규식 → 그래도 빠지면 LLM(JSON 스키마, 질문에 단서가 있는 값만 채택)
     → ② 빈 값 채우기: 질문 > 로그인 전공 > 마이페이지 목표 > 가장 가까운 시험일 / 그래도 없으면 되묻기
     → ③ 유사 집단 통계: ReviewStatsQuery → 합격자 하루 공부시간 평균·중앙값·최소·최대 (10건 미만이면 조건 확대, 그래도 부족하면 통계 미사용)
     → ④ Java 계산: 남은 일수, 총 가용시간, 3단계(3주 이상이면 주 단위로 끊음), 과목별 시간(이해도 가중치 1.3/1.0/0.7)
     → ⑤ LLM 답변(합격 기준 문장 포함) → 숫자 검증(자료에 없는 숫자면 1회 재요청 → 실패 시 Java 기본 안내) / LLM(Claude API) 사용 불가 → 원인과 함께 Java 기본 안내
     → ⑥ 답변 저장
```
숫자는 모두 Java·SQL 이 계산하고 LLM 은 문장만 쓴다 (기획안 3.1, 5.5).

## 5. 검증한 것 / 확인 필요
- 검증함: DB 스크립트 실행(passpace_erd.sql 기준 테이블 20, FK 36, 더미 48), 저장소 SQL 전부, 순수 로직 단위 테스트 8개, 실제 더미 데이터로 챗봇 흐름(예시 질문 → 비전공·필기 합격 후기 14건 통계, 숫자 검증, Ollama 꺼짐 대체, 조건 확대)
- **IntelliJ 에서 첫 Gradle 빌드·실행은 아직 확인하지 않았다** (작성 환경에서 Maven 저장소 접속 불가). 오류가 나면 메시지를 그대로 공유
- 확인 필요 `// 확인 필요:` 표시
  - 시험일정 API 의 docExamEndDt, docPassDt, prac* 필드 이름 (ExamScheduleJsonParser)
  - 2027 필기 4과목 이름 (큐넷 출제기준) / 합격 기준 문장
  - 단계 비율(30·40·50%)과 이해도 가중치(1.3/1.0/0.7)는 초기 설계값
- 범위 밖 (확장 지점): 복수 자격증, 타이머·학습기록, 계획 저장(STUDY_PLANS), 재편성(AI_PLAN_PROPOSALS), 관심자격 추천, 관리자 인증, 정기 수집 스케줄러

## 6. 2026-11-19 변경 사항 (동건: 계획 저장·요일별 시간·재편성)

`feature/passpace-chat-donggeon` 에 `develop`(한결 학습기록 API, 용성 과목 언급 수집·중앙값 집계)을 합친 뒤 아래를 추가했다. 새 테이블은 없다. 앱(Flutter)의 화면 변경은 앱 저장소 README 에 적었다.

| 파일 | 바뀐 것 |
|---|---|
| `repository/ChatPlanStore` | 저장한 계획을 지우지 않고 목록으로 관리(목록·한 건 조회·전환·삭제), 요일별 가능시간 저장, 재편성용 조회와 추천 기록 |
| `controller/ReviewBasedPlannerController` | `/save?activate=`, `/plans/**`, `/replan/**` 추가. 요청의 `weekdayMinutes` 전달 |
| `service/MultiGoalPlanCalculator` | 요일별 공부시간(`weekdayMinutes`) 계산, 최소 학습 블록 45분 → 50분 |
| `service/PlanReplanner` (새 파일) | 밀림 판단(계획 전체의 20%)과 남은 공부량 재배정 요청 (DB 없는 순수 계산) |
| `static/js/chatbot.js` | 안내 문구의 블록 시간만 50분으로 수정 |

- **계획 상태**: 사용자당 `ACTIVE` 1건(지금 쓰는 계획), 나머지는 `REPLACED`(보관). 학습기록(한결) 쪽이 읽는 두 값만 쓴다.
- **요일별 시간**: 요청에 `weekdayMinutes`(`{"1":60,"6":240}`)가 있으면 그 요일에만, 그날의 시간까지만 배정한다. 없으면 기존과 같은 결과다. 저장할 때 `STUDY_PLANS.weekday_minutes` 에 요일별 가능시간을 남긴다.
- **재편성 추천**: 어제까지 배정된 시간 중 하지 못한 시간이 계획 전체의 20% 이상이면 `GET /replan` 이 다시 짠 일정을 돌려준다. 수락·거절은 `AI_PLAN_PROPOSALS`(`delay_reason_type = 'BEHIND_SCHEDULE'`, `model_name = 'RULE'`)에 남긴다. `STUDY_SESSIONS` 는 읽기만 한다.
- **DB**: `db/10_review_subject_mentions.sql`(용성)을 실행해야 과목 언급이 저장된다.
- **테스트**: `gradlew test` 117개 통과 (`MultiGoalPlanCalculatorTest` 요일별 시간·50분 블록, `PlanReplannerTest` 추가).
- 5장의 "범위 밖" 중 **계획 저장(STUDY_PLANS)** 과 **재편성(AI_PLAN_PROPOSALS)** 은 이번에 구현했다. 재편성은 정기 스케줄러가 아니라 앱에서 홈을 열 때 확인한다.

## 6-1. 2026-11-20 변경 사항 (용성: 총학습량·과목 비율 db/11)

| 바뀐 것 | 내용 |
|---|---|
| 총학습량 계산 | 추정값(준비일수 × 하루시간 중앙값)을 섞을지 전공 그룹마다 따로 정하던 것을 통일. 전공 전체 직접 값이 10건 이상이면 모든 그룹에서 추정값을 뺀다 (정처기 필기 '전공' 42건 > '전공 전체' 34건이던 문제 해결) |
| 일지형 후기 읽기 | '합계 23시간 56분', '4h 3m' 표기를 읽는다. 날짜로 시작하는 줄이 3줄 이상이면 과목별 시간을 합산 |
| 수집 범위 | velog 후기 6개·hwankr 글 주소, 티스토리 검색어 41개 추가 |
| 과목 언급 끝까지 자동 | 200건씩 이어서 처리. 차단(403·429)·남은 0건·진행 없음·멈추기 버튼에서 멈춤. 자동 실행 중 수동 실행은 받지 않음 |
| 앱 관리자 화면 | 남은 수·진행률·읽는 글 3초마다 표시, 건수(1~200) 입력, 끝까지 자동·멈추기, 재집계 결과 표 |

- **과목별 학습시간 (팀 합의)**: 후기 991건 중 과목별 시간이 적힌 글이 4건뿐이라 실측 평균 대신 **총학습량 × 과목 비율**로 제공한다. 비율 근거는 ADsP·컴활 1급은 공식 문항·배점, 정처기·SQLD는 합격자 1인 일지(db/03)
- **db/11** (`db/11_provisional_subject_ratio.sql`): 새 테이블이 아니라 `STUDY_REFERENCE_STATS` 에 과목별 줄 8개 추가 (`stat_status = 'PROVISIONAL'`, 전공 구분 없음, 기준일 2026-11-20). 값은 비율로만 쓰인다 → 실제 과목 시간 = 총학습량 실측 중앙값 × 비율 (예: ADsP 10/10/10 → 6/6/18)

| 자격증 | 시험 | 과목 | 값 | 근거 |
|---|---|---|---|---|
| ADsP | 필기 | 데이터 이해 / 데이터분석 기획 / 데이터분석 | 8.74 / 8.74 / 26.22 | 문항 10·10·30 / 50 |
| 컴활 1급 | 필기 | 컴퓨터 일반 / 스프레드시트 일반 / 데이터베이스 일반 | 12.83 각각 | 문항 20 / 60 |
| 컴활 1급 | 실기 | 스프레드시트 실무 / 데이터베이스 실무 | 30.00 각각 | 배점 100 / 200 |

- **실행·되돌리기**: 팀원은 DBeaver 에서 db/11 을 한 번 실행 (여러 번 실행해도 안전). 되돌리기는 파일 맨 아래 주석의 DELETE 문
- **테스트**: 서버 `gradlew test` 성공, 앱 `flutter test` 245개 통과. 재집계에서 추정값이 섞인 전공 줄이 사라진 것, db/11 실행 후 8줄 확인

## 7. 2026-11-22 변경 사항 (동건: 과목 비율·외부 LLM)

| 파일 | 바뀐 것 |
|---|---|
| `controller/ReviewBasedPlannerController.applyReference` | 과목별 시간을 고정 비율(`StudyHoursEvidence`)로 다시 나누지 않고 `ref.subjects()` 의 시간(용성 집계: 수집 데이터 총 학습시간 × 과목 비율)을 그대로 쓴다. 후기 실측이 없거나 과목 수·이름이 맞지 않거나 과목 시간이 비어 있을 때만 기존 고정값을 쓴다 |
| `service/PlanCalculator`, `service/ChatServiceImpl` | 상담 채팅의 단일 계획 답변도 같은 과목 비율을 쓴다: 과목별 시간 = 총 가용시간 × (`ref.subjects()` 시간 비율 × 이해도 가중치). 참고 시간이 없으면 예전처럼 똑같이 나눈다 |
| `client/ClaudeClient` (새 파일) | 챗봇 LLM 호출을 로컬 Ollama 에서 Claude API(공식 Java SDK)로 바꿨다. `client/OllamaClient`, `OllamaUnavailableException` 삭제 → `LlmUnavailableException` |
| `service/AnswerComposer`, `service/ConditionExtractor` | `ClaudeClient` 사용. temperature 인자는 없앴다 (모델이 받지 않음). 조건 추출 JSON 스키마에 `additionalProperties: false` 추가 |
| `build.gradle` | `com.anthropic:anthropic-java:3.3.0` 추가 → **팀원 Gradle 새로고침 필요** |
| `application.yml` | `passpace.ollama.*` → `passpace.claude.*` (api-key, model, effort, max-tokens, timeout-seconds) |

- **API 키**: https://platform.claude.com 에서 발급. 환경변수 `ANTHROPIC_API_KEY` 또는 `application-local.yml` 의 `passpace.claude.api-key` 에 넣는다 (저장소에 올리지 않음).
- **키가 없거나 호출이 실패하면** 예전 Ollama 가 꺼졌을 때와 같이 Java 기본 안내로 답한다. 숫자는 여전히 Java·SQL 이 계산하고 LLM 은 문장만 쓴다.
- **모델**: 기본 `claude-sonnet-5-5`, `effort: low`. 더 줄이려면 `passpace.claude.model: claude-haiku-5-5`.
- **테스트**: `gradlew test` 133개 통과. 실제 Claude API 호출(claude-sonnet-5-5)로 상담 답변 생성 확인.


## 한결 브랜치 로컬 실행

IntelliJ 실행 설정에 팀원 PC의 MariaDB 비밀번호를 `SPRING_DATASOURCE_PASSWORD`로, 개발용 서명 키를 `JWT_SECRET`으로 지정하세요. 서명 키는 충분히 긴 무작위 값(최소 64바이트)을 사용하고 Git에 올리지 마세요. DB 사용자와 주소가 다르면 `SPRING_DATASOURCE_USERNAME`과 `SPRING_DATASOURCE_URL`도 지정하세요. 개인 설정은 `src/main/resources/application-local.yml`에서도 지정할 수 있습니다.
