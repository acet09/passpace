# 패스페이스(PASS PACE) 정보처리기사 실험판 - 완성 코드

3명이 각자 맡은 영역을 만들고 합쳤을 때 동작하는지 실험하기 위한 **완성본**이다.
다음 단계에서 이 코드의 함수·변수 껍데기만 남긴 **빈칸 버전**을 만들어 각자 채워 넣는다.

## 1. 담당과 폴더

```
src/main/java/com/passpace/
├─ PasspaceApplication.java      실행 시작점
├─ common/   ★ 공통 계약 (혼자 수정 금지)  LoginUser, SessionConst, 코드값 Enum, 인터페이스 3개
├─ global/   공통 예외 처리 (JSON API)
├─ user/     [한결] 메인·로그인·회원가입·마이페이지
├─ collect/  [용성] 시험일정 API 수집, 후기 크롤링, 후기 통계 조회(SQL)
└─ chat/     [동건] 로컬 LLM 챗봇
src/main/resources/
├─ templates/fragments/layout.html   [한결] 공통 헤더·푸터
├─ templates/fragments/chatbot.html  [동건] 챗봇 위젯 (모든 페이지 하단에 들어감)
├─ templates/{home, user/*}          [한결]
├─ templates/collect/admin.html      [용성] 수집 실행 화면
├─ prompts/                          [동건] LLM 지시문
└─ collect/                          [용성] 후기 탐색 목록·직접 지정 URL, 샘플 시험일정
db/  01_schema(= passpace_erd.sql) → 02_schema_ext → 03_seed (04 는 더미 삭제)
```

| 담당 | 화면·주소 | 쓰는 테이블 | 읽는 테이블 |
|---|---|---|---|
| 한결 | `/`, `/login`, `/signup`, `/mypage`, `/logout` | USERS, USER_GOALS, GOAL_SUBJECTS | EXAM_ROUNDS, CERTIFICATION_SUBJECTS |
| 용성 | `/admin/collect` (POST `/admin/collect/exam`, `/admin/collect/reviews`, `/reviews/discover`, `/reviews/preview?url=`, `/reference-stats`) | DATA_SYNC_JOBS, EXAM_ROUNDS, EXAM_SCHEDULE_CHANGE_LOGS, PASS_REVIEWS | CERTIFICATIONS |
| 동건 | 챗봇 위젯, POST `/api/chat` | CHAT_CONVERSATIONS, CHAT_MESSAGES | PASS_REVIEWS(계약 경유), EXAM_ROUNDS, CERTIFICATION_SUBJECTS |

## 2. 세 영역이 만나는 곳 (합칠 때 확인할 곳은 여기뿐)

세 영역은 서로의 클래스를 import 하지 않는다. 연결은 아래 세 가지뿐이다.

| 연결점 | 만드는 쪽 | 쓰는 쪽 | 내용 |
|---|---|---|---|
| 세션 `SessionConst.LOGIN_USER` → `LoginUser` | 한결(로그인 시 저장) | 동건(챗봇 사용 가능 여부·전공·회원 ID) | **챗봇은 로그인 사용자 전용**. 이름·타입이 다르면 로그인해도 챗봇이 잠김 |
| 화면 model `loginUser` | 한결 `LoginUserModelAdvice`(모든 @Controller 화면) | 동건(위젯 잠금/활성), 한결(헤더) | 없으면 위젯이 항상 "로그인 후 이용" 으로 보임 |
| `UserStudyProfileQuery` | 한결 `user.query.JdbcUserStudyProfileQuery` | 동건 | 마이페이지의 목표 시험일·하루 시간·과목별 이해도 |
| `ReviewStatsQuery` | 용성 `collect.stats.JdbcReviewStatsQuery` | 동건 | 조건에 맞는 VALID 후기 목록 |
| `ReviewExtractor` | 용성 `collect.extract.RuleBasedReviewExtractor` | 용성(수집 서비스) | 나중에 동건의 LLM 추출기로 교체 가능 |
| 화면 `fragments/chatbot :: widget` | 동건 | 한결(모든 페이지 하단), 용성(관리 화면) | CSS·id 는 `pp-chat-` 접두어 |
| DB 테이블 | 표 1 참고 | | 테이블마다 쓰는 사람은 한 명 |

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
그다음 `db/01_schema.sql` → `db/02_schema_ext.sql` → `db/03_seed.sql` 을 차례로 열고 **스크립트 실행(Alt+X)**.
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
