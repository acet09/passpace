# 패스페이스(PASS PACE) 정보처리기사 실험판 - 완성 코드

3명이 각자 맡은 영역을 만들고 합쳤을 때 동작하는지 실험하기 위한 **완성본**이다.
다음 단계에서 이 코드의 함수·변수 껍데기만 남긴 **빈칸 버전**을 만들어 각자 채워 넣는다.

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
├─ client/      외부 API·페이지 가져오기 (Ollama, 공공데이터, 후기 페이지)
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
- (챗봇) Ollama + `qwen3.5:4b` (6GB GPU) 또는 `qwen3.5:9b` (10GB GPU) — 없어도 앱은 실행되고 챗봇은 "기본 안내"로 답한다
- NVIDIA 드라이버가 오래되면 Ollama 에서 `CUDA error: device kernel image is invalid` 가 난다 → 드라이버 최신화

### 3-2. DB (DBeaver, root 계정)
```sql
CREATE USER IF NOT EXISTS 'passpace'@'localhost' IDENTIFIED BY 'passpace';
GRANT ALL ON passpace_merged.* TO 'passpace'@'localhost';
```
그다음 `db/01_schema.sql` → `db/02_schema_ext.sql` → `db/03_seed.sql` → `db/08_add_user_role.sql` 을 차례로 열고 **스크립트 실행(Alt+X)**.
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
     → ⑤ LLM 답변(합격 기준 문장 포함) → 숫자 검증(자료에 없는 숫자면 1회 재요청 → 실패 시 Java 기본 안내) / Ollama 사용 불가 → 원인과 함께 Java 기본 안내
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
