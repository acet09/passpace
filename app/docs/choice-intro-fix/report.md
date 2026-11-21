# 수집 선택값 표시·소개 단계 제거 · 2026-11-15

## 반영한 화면 수정

- 후기 수집의 사이트·방식을 선택해도 글자가 보이지 않던 문제를 재현했다. DropdownButtonFormField의 작은 기본 표시 높이에 메뉴 항목의 세로 여백이 함께 들어가 글자가 잘렸다. 기본·150·200% 글자에서 실제 글자 높이보다 표시 영역이 작은 것을 확인했다.
- lib/ui/admin_widgets.dart의 AdminChoice에서 선택값 표시를 메뉴 항목과 분리하고 높이가 내용에 맞게 늘어나도록 수정했다. 같은 공통 선택칸을 사용하는 관리자 조회 조건·사이트 선택도 적용된다. 선택값·요청·저장 방식은 유지했다.
- lib/ui/auth_intro.dart에서 ‘목표 설정 → 학습계획 → 오늘의 학습’ 줄과 전용 장식 위젯만 제거했다. 소개 제목·설명·로그인·회원가입 동선은 유지했다.

[변경 전후 화면](index.html) · [전체 테스트](test-run.txt) · [정적 검사](analyze-run.txt) · [Android 화면 검증](android-run.txt)

## 검증

- 단위·화면 테스트 92개 통과, 정적 검사 오류·경고·정보 0건. 새 검사는 텍스트 위젯 존재 여부와 함께 실제 렌더링 높이를 검사하고, 선택 변경 후 값과 글자 표시가 유지되는지 확인한다. 기존 로그인 입력 보존·요청·가입 복귀 검사도 통과했다.
- Android SAMPLE 시나리오 1개 통과. 수집 사이트 목록 열기, 티스토리·복구 수집 선택 후 표시, 소개 단계 제거와 로그인 입력란을 확인하고 이미지 3개를 촬영했다. MockClient·메모리 계정만 사용했고 기존 계정·DB에 쓰지 않았다.
- 정상 진입점 lib/main.dart로 APK를 갱신·설치했다. 로그인 화면 진입, 핫 리로드 성공과 Dart 실행 오류 0건을 확인했고 runtime-verification.json에 기록했다.
- 작업 전후 팀 소스·SQL·설정 196개와 기존 테스트 백엔드 66개의 해시가 동일하고 Git 변경도 0건이었다. 앱의 기존 생산 파일 56개 중 admin_widgets.dart·auth_intro.dart만 바뀌었으며 나머지 54개는 동일하다. 실제 API 쓰기·외부 사이트 수집·개인 휴대폰 설치·TalkBack은 이번 검증에 포함하지 않았다.

수정 범위: 위 UI 2개, test/admin_choice_visibility_test.dart·test/auth_entry_test.dart, integration_test/choice_intro_test.dart·test_driver/choice_intro_driver.dart와 앱 검증 문서. API·데이터 모델·세션·저장소·계산·인증·패키지·환경·Android 코드·팀원의 TODO는 수정하지 않았다. 최종 비교는 scope-verification.json에 기록했다. 생성 도구가 바꾼 동등한 SDK 경로 표기는 원래 해시로 정확히 복원했다. 기존 서버의 collect-data·로그 등 실행 데이터는 소스 비교에서 제외하며 편집·삭제하지 않는다.

새 APK: [app-debug.apk](../../build/app/outputs/flutter-apk/app-debug.apk)

## 타이머·학습기록·개인 학습통계: 확인한 현재 상태

아래는 **현재 팀 프로젝트 passpace11144에 추가할 설계안**이다. 이번 작업에서 백엔드 구현이나 DB 변경을 수행하지 않았다.

| 직접 확인한 근거 | 현재 상태 |
|---|---|
| [db/01_schema.sql:277](C:/Users/std66/passpace11144/db/01_schema.sql:277) | STUDY_SESSIONS가 이미 있다. session_id·user_id·task_id·study_date·start_time·end_time·actual_minutes·input_method·digestion_level을 정의한다. |
| 같은 스키마 282~283행 | start_time·end_time은 날짜가 없는 TIME이다. 날짜를 포함한 UTC 시점이나 일시정지 구간을 보관하는 구조는 없다. |
| Java 소스의 STUDY_SESSIONS·actual_minutes·timer·study/statistics 경로 검색 | 개인 기록 저장·조회, 타이머 상태 변경, 개인 학습시간 통계를 제공하는 구현은 발견하지 못했다. StatsCalculator 등 후기 통계는 별개다. |
| [ChatPlanStore.Task:35](C:/Users/std66/passpace11144/src/main/java/com/passpace/repository/ChatPlanStore.java:35), findActive 조회 112행 | DB에는 task_id가 있으나 앱에 주는 할 일에는 날짜·시험명·과목명·분만 있다. 현재 응답에는 task_id가 없다. |

계획 계산 DTO에 있는 actualMinutes·진도 입력은 과거 공부량을 계산에 반영하는 값이다. 개인의 학습 세션을 저장·조회하는 기능과는 별개이며, 제거했던 입력 UI를 다시 추가하지 않았다.

## 필요한 추가 구현

| 기능 | 백엔드 추가 내용 | DB 활용·추가 제안 |
|---|---|---|
| 학습기록 | 본인 기록 생성·기간별 목록·상세 API, 타이머 종료 기록·직접 입력 구분, 과목/계획 연결, 수정 시 이력 보존 | 기존 STUDY_SESSIONS 재사용. 기록된 시간은 actual_minutes에 정수 분으로 저장. 계획 밖 기록도 과목별로 묶으려면 과목 식별 관계를 추가하거나 별도로 조회·보관해야 한다. |
| 타이머 | 시작·현재 상태·일시정지·재개·종료 API, 동시 실행 제한, 종료 시 기록 자동 생성, 앱/서버 재시작 후 상태 복원 | 예: 새 STUDY_TIMERS에 사용자·할 일·상태·version, 새 STUDY_TIMER_SEGMENTS에 구간의 UTC 시작/종료 시점. 이는 제안 이름이며 아직 없는 테이블이다. |
| 개인 학습통계 | 날짜 범위의 총 기록 시간·일별 합계·과목별 합계·기록 건수 API | 우선 STUDY_SESSIONS를 합산해 제공한다. 초기에는 별도 통계 테이블이 필요하지 않다. (user_id, study_date) 등 조회 인덱스를 검토한다. 계획 배정 시간과 실제 기록 시간은 분리한다. |
| 학습계획 연결 | 현재 계획 조회의 할 일에 taskId를 추가하고 필요한 과목 식별값을 제공 | task_id로 본인 계획인지 검증한다. 재편성 후에도 과거 기록이 가리키는 기존 할 일·계획 버전을 보존한다. 날짜·과목명 문자열만으로 연결하지 않는다. |

기존 Java/Spring Boot·MariaDB와 로그인 체계를 유지하고 study 기능의 Controller·Service·Repository·DTO를 추가하면 된다. 업무·시간 계산과 트랜잭션은 Service, DB 접근은 Repository가 맡는다. 기존 스키마 파일·적용 이력을 덮어쓰지 않고 별도 증분 SQL/현재 사용하는 마이그레이션 방식으로 추가한다.

## API 예시 — 현재 존재하는 주소가 아님

| 제안 API | 역할 |
|---|---|
| GET /api/study/timer | 로그인한 사용자의 현재 타이머와 서버 시각 조회 |
| POST /api/study/timer/start | taskId 또는 선택 과목으로 시작 |
| POST /api/study/timer/{timerId}/pause·resume·stop | 일시정지·재개·종료. stop은 실제 기록 생성까지 원자적으로 처리 |
| GET /api/study/sessions?from=YYYY-MM-DD&to=YYYY-MM-DD | 본인 기록 목록 |
| POST /api/study/sessions | 누락한 공부시간 직접 입력 |
| GET /api/study/statistics?from=YYYY-MM-DD&to=YYYY-MM-DD | 기간 합계·일별/과목별 기록 시간 |

통계 응답은 기간, totalActualMinutes, 날짜별 actualMinutes·sessionCount, 과목별 actualMinutes처럼 단위를 분명히 한다. 기록이 없는 날은 ‘기록 없음’ 또는 ‘기록된 시간 0분’으로 다루고 학습 완료·휴식으로 추정하지 않는다.

## 반드시 함께 정할 동작

- 사용자 ID는 로그인 정보에서 얻고, taskId·timerId·sessionId의 소유권을 서버에서 확인한다. 회원이 다른 회원의 시간을 읽거나 바꾸지 못하게 한다.
- MVP 제안은 사용자당 진행 중 타이머 1개다. 웹·앱에서 동시에 누르거나 종료를 재전송해도 중복 기록이 생기지 않도록 사용자 행 잠금·version과 중복 요청 식별키를 사용한다.
- 계획 승인·재편성과 기록 처리를 직렬화하려면 양쪽이 같은 사용자 행 잠금 규약을 사용해야 한다. 타이머 기능만 잠그는 것으로 기존 계획 저장과의 동시 처리가 모두 해결되는 것은 아니다.
- 일시정지 구간 마감, 타이머 상태 변경, 최종 학습기록 생성은 같은 트랜잭션에서 처리한다. MariaDB의 FOR UPDATE는 트랜잭션 안에서 사용해야 한다. [MariaDB 공식 설명](https://mariadb.com/docs/server/reference/sql-statements/data-manipulation/selecting-data/for-update), [Spring 트랜잭션 설명](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/annotations.html).
- 날짜는 Asia/Seoul, 시점은 날짜까지 포함한 UTC로 보관한다. Java의 Instant 등으로 시점을 다루고, 유효한 실행 구간을 서버에서 합산해 정수 분으로 확정한다. 초 단위 화면 표시 때문에 매초 DB에 쓰는 구조는 필요하지 않다. [Java 21 Instant](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/time/Instant.html).
- 앱을 닫아도 실행을 계속할지, 자정이 지나면 날짜별로 나눌지, 분 미만 시간을 어떻게 처리할지, 장시간 방치와 기록 정정을 어떻게 처리할지 팀 정책을 정한다. 프론트엔드에서 보낸 경과 시간만 신뢰해 저장하지 않는다.

권장 순서는 **기록 저장·조회 → 타이머와 자동 기록 → 개인 통계**다. 이 기반이 갖춰지면 Flutter 앱에 실제 기능을 연결할 수 있다. 기존 후기 분석 통계나 계획 시간 그래프를 개인 실공부 통계로 대체해서 표시하지 않는다.
