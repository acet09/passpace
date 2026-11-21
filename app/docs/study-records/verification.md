# 학습기록·개인 통계 앱 연결 검증

2026-11-15 · 사용자 승인 범위: Flutter 앱만 수정, 기존 팀/테스트 백엔드는 읽기 전용.

## 적용 결과

- 하단 **기록** → **공부시간 추가**에서 날짜와 실제 공부한 정수 분을 저장한다.
- **기록 목록**에서 최근 7일·30일·직접 선택한 기간(최대 366일)의 기록과 이전 페이지를 조회한다.
- **개인 통계**는 동일 기간의 서버 합계와 일별 실제 분을 꺾은선·막대로 표시한다. 월은 위쪽, 일 숫자는 간격을 두어 표시한다. 날짜 이동과 일별 숫자 확인도 제공한다.
- 기존 오늘·학습계획·상담·내 정보와 관리자 진입은 유지했다. 계획 시간을 실제 공부시간으로 사용하지 않는다.
- 날짜는 Asia/Seoul 기준이다. 최근 기간은 재조회·앱 복귀·탭 진입 시 오늘까지 갱신한다. 연도를 넘는 기록은 날짜에 연도를 표시한다.

## 수정 파일

| 파일 | 이유 |
| --- | --- |
| `lib/data/api.dart` | 기존 인증/에러 helper로 세 API 호출 추가, 불확실한 저장 결과 구분 |
| `lib/data/study_models.dart` (신규) | 기록·페이지·일별 통계 응답 검증 |
| `lib/ui/dashboard.dart` | 기록 탭 추가, 상담/내 정보 인덱스 연결 |
| `lib/ui/study_records.dart` (신규) | 조회 기간·목록·통계·페이지·오류·권한·늦은 응답 처리 |
| `lib/ui/study_record_form.dart` (신규) | 날짜/분 입력·중복 탭 차단·실패 시 입력 보존 |
| `lib/ui/study_chart.dart` (신규) | 서버 실제 분 그래프·접근 가능한 숫자 보기 |
| `test/study_api_test.dart`, `study_records_test.dart`, `study_chart_test.dart`, `support/study_fixture.dart` (신규) | 계약·사용 흐름·오류·경합·접근성 회귀 검사 |
| `integration_test/study_live_test.dart`, `integration_test/support/study_api_fixture.py`, `test_driver/study_driver.dart` (신규) | 별도 DB/합성 계정의 실제 API 검증과 Android 캡처 |
| `docs/verification.md`, `docs/study-records/` | 실행 증거·변경 범위·결과 기록 |
| `android/local.properties` | Flutter가 빌드 중 로컬 SDK 속성 파일을 자동으로 다시 기록함. 직접 편집하지 않았고 원본 바이트 복원본은 확보하지 못함 |

API 기존 메서드의 업무 동작, `Session`, 보안 저장소, 기존 모델, 로그인/회원가입 화면, 기존 관리자 코드, pubspec/lock, Gradle·Manifest·실행 스크립트는 직접 변경하지 않았다. 최종 해시 차이는 `scope-result.json`에 기록한다.

## 실제 검증

- 원래 팀 프로젝트를 수정하지 않고 이전에 검증한 동일 소스의 Spring Boot JAR를 재사용했다. 여섯 학습 API Java 파일은 현재 팀 파일과 바이트가 같은지 확인했다.
- 별도 임시 MariaDB 데이터 경로와 비운영 포트를 확인한 뒤 격리 서버를 실행했다. 앱은 메모리 세션/초안 저장소와 합성 `SAMPLE` 계정만 사용했다. 원래 계정/DB에는 쓰지 않았다.
- 실제 Android 에뮬레이터에서 로그인, 45분 저장, 기록 재조회, 서버 합계 +45분, 꺾은선/막대 전환, 최근 30일, 탭 재진입을 확인했다. 서버 초기 합성 기록 160분 + 앱 저장 45분 = 205분이었다.
- `live-result.json`: 8개 확인 항목, 실제 HTTP와 SQL 사용. 테스트 완료 후 격리 서버/DB 종료, 임시 로그인 설정 제거.
- 일반 `lib/main.dart` 진입점으로 debug APK를 새로 빌드했다. 테스트 진입점/합성 계정 관련 표식이 APK의 kernel에 없는지 검사했다(`apk-result.json`).
- APK를 에뮬레이터에 갱신 설치했다. 일반 앱의 AuthScreen을 위젯 검사로 확인하고 핫 리로드 성공, 런타임 오류 없음도 확인했다(`runtime-result.json`).

## 모의 검증

- `flutter test --no-pub --reporter expanded`: **124개 통과**. 기존 92개 + 신규 32개. `all-tests.log` 참조.
- `flutter analyze --no-pub`: **문제 없음**. `analyze.log` 참조.
- MockClient: Bearer/JSON 계약, 직접 입력, 400/409 입력 보존, 이중 탭, 저장 후 응답 유실, 5xx/잘못된 응답, 401/403, 빈 목록/0분/오류 구별, 페이지, 기간 변경 경합, 인증 갱신 경합.
- 입력 중 인증이 바뀌면 이전 입력을 차단한다. 소수/음수/긴 숫자를 다른 값으로 바꾸지 않고 거부한다. 두 문제의 수정 전 회귀 실패도 확인했다(`form-safety-red.log`).
- 날짜가 바뀐 앱 복귀와 30/366일 그래프 양끝 선택도 수정 전 실패를 확인한 뒤 최종 통과했다(`date-resume-red.log`, `chart-touch-red.log`).
- 320·360·412 너비, 글자 150%/200%, 키보드 하단 300 높이에서 기록/통계/입력과 버튼을 검사했다. 실제 TalkBack 음성 청취를 대신하는 검사는 아니다.
- 새 기능 전의 검사에서 기존 92개는 통과했고 기록 탭 검사는 실제로 실패했다(`baseline-test.log`).

## 화면

아래는 모두 **격리된 실제 API의 합성 기록**이다. 원래 계정 데이터와 완성도 지표를 만들지 않았다.

| 저장 전 목록 | 입력 | 저장 후 목록 |
| --- | --- | --- |
| ![저장 전](<C:/Users/std66/Documents/ChatGPT/PASS_FACE _ TEST/passpace_mobile/docs/study-records/screenshots/live-study-history-before.png>) | ![날짜와 분 입력](<C:/Users/std66/Documents/ChatGPT/PASS_FACE _ TEST/passpace_mobile/docs/study-records/screenshots/live-study-input.png>) | ![저장 후](<C:/Users/std66/Documents/ChatGPT/PASS_FACE _ TEST/passpace_mobile/docs/study-records/screenshots/live-study-history.png>) |

| 꺾은선 | 막대 | 최근 30일 |
| --- | --- | --- |
| ![개인 꺾은선 통계](<C:/Users/std66/Documents/ChatGPT/PASS_FACE _ TEST/passpace_mobile/docs/study-records/screenshots/live-study-line.png>) | ![개인 막대 통계](<C:/Users/std66/Documents/ChatGPT/PASS_FACE _ TEST/passpace_mobile/docs/study-records/screenshots/live-study-bars.png>) | ![30일 통계](<C:/Users/std66/Documents/ChatGPT/PASS_FACE _ TEST/passpace_mobile/docs/study-records/screenshots/live-study-month.png>) |

## 제약·보류·미검증

- 현재 계획 조회 응답에는 `taskId`가 없고 기존 통계/기록 응답에도 연결에 필요한 계획 버전이 없다. 앱에서 새 기록은 **날짜·시간의 미연결 수동 기록**으로 저장한다. 기존 서버 기록의 과목명/계획 연결 정보는 그대로 표시한다. 과목/계획 ID를 추정하지 않았다.
- 타이머·기록 수정/삭제·완료율·연속 학습일은 이번 API 연결에 포함하지 않았다. 특히 `completionRate:null`을 수치로 만들지 않았다.
- 서버에 idempotency 계약이 없어 영속적인 중복 제거는 보류한다. 앱은 POST를 자동 재전송하지 않으며 결과 불명 시 목록을 먼저 확인하도록 한다. 값이 같은 정상 기록을 임의로 중복 삭제하지 않는다. 앱 강제 종료/다른 기기/의도적 재입력 전체의 중복 방지는 보장하지 않는다.
- 두 조회 API는 별도 요청이므로 다른 기기의 동시 저장에 대한 원자적 스냅샷은 보장하지 않는다. 새로고침으로 다시 조회할 수 있다.
- 실제 휴대폰(이번에는 연결된 USB 기기 없음), TalkBack 음성, 운영 계정 저장, 배포/서명된 release, 기존 회원의 로그인 성공은 이번 실제 검증 대상이 아니다.
- 루트의 Java/React/쓰기 통합 검증은 앱 변경을 위한 검증으로 실행하지 않았다. 기존 서버 소스/설정/SQL을 비교했고 앱 전체 테스트·정적 검사·격리 HTTP/Android 검증을 수행했다.

## 갱신 및 실행

- APK: `C:/Users/std66/Documents/ChatGPT/PASS_FACE _ TEST/passpace_mobile/build/app/outputs/flutter-apk/app-debug.apk` (debug, `apk-result.json`에 SHA-256 기록).
- 에뮬레이터에는 갱신 설치/실행했다. 물리 휴대폰은 이 APK로 갱신 설치한다.
- 앱 개발 실행: 앱 폴더에서 `flutter run -d emulator-5554`. 실행 중 `r` 또는 Android Studio의 Hot Reload를 사용한다.
- 최종 확인 당시 기본 서버 `http://127.0.0.1:8080`은 응답하지 않았다. 실제 사용하려면 기존 `passpace_mobile/서버 켜기.cmd`를 실행한다. 이 기존 실행기는 현재 팀 소스를 `bootRun`으로 실행하며 이번 작업에서 변경하지 않았다.
- 서버 실행 후 에뮬레이터는 기존 `http://10.0.2.2:8080`, USB 휴대폰은 기존 USB 연결/서버 설정을 사용한다. 백엔드를 이번 앱에 포함하거나 호스팅한 것은 아니다.

## 독립 코드 검토

최종 읽기 전용 검토에서 전체 운영 변경 파일과 서버 DTO/기존 세션의 호환성을 확인했다. 계정 캡처·입력 값 변환·날짜 복귀·그래프 좌표·연도 표시 지적을 수정하고 회귀 검사로 확인했다. 미해결 중요 코드 지적은 없다. 검토자는 직접 빌드/테스트를 실행하지 않았으며 실제 실행 증거는 위 로그와 실행 담당의 결과다.
