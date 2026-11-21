# 학습기록 날짜·공부시간 수정 검증

2026-11-15. 사용자 승인 범위: 기존 학습기록 Java6파일과 Flutter 앱. 다른 팀원 코드·DB 구조·웹·환경 버전은 유지한다.

## 적용

**기록 → 해당 기록의 수정 → 날짜·실제 공부시간 입력 → 수정 내용 저장**으로 사용한다. 기존 값을 먼저 채우며 취소/입력 오류에서는 기록을 바꾸지 않는다. 수정 후 기록과 개인 통계는 서버에서 다시 조회한다. 기존 기간 밖 날짜로 옮기면 해당 날짜로 조회 기간을 바꾼다.

새 API는 `PATCH /study/sessions/{sessionId}` 하나다. 기존 POST/GET 기록 및 GET 통계와 함께 총4개이며 경로·입출력·담당 파일은 [API 목록](<C:/Users/std66/Documents/ChatGPT/PASS_FACE _ TEST/passpace_mobile/docs/api-contract.md>)에 기록했다. 이 목록은 이후 “추가한 API” 요청에 사용하는 프로젝트 기록이다.

- 날짜와 정수 분만 변경한다. 같은 기록 ID·과목·계획·입력 방식·시작/종료 시간·이해도는 보존한다. 현재 직접 입력(MANUAL) 기록만 수정한다.
- 사용자/전공/소유권 검증, 사용자 행 및 기록 행 잠금, 원래 날짜·분 비교를 수행한다. 다른 기기에서 값이 바뀌면409로 거부한다.
- 같은 날짜 합계는 자기 원래 분을 제외한 뒤1440분 한도를 검사한다. 날짜 이동 시 대상 날짜 한도도 확인한다.
- 새 version 컬럼이나 migration은 추가하지 않았다. 값 비교는 A→B→A 전체 변경 이력 감지·감사 로그·영속적 idempotency를 보장하지 않는다.
- PATCH 자동 재전송은 없다. 결과 불명 시 이전/요청 날짜를 확인하며 해당 ID를 찾거나 그날의 페이지를 모두 조회해야 확인을 마칠 수 있다. 입력·인증·계정 변경 보호는 유지한다.

## 실제 검증

| 대상 | 결과 | 증거 |
| --- | --- | --- |
| 격리 소스 복사본·실제 MariaDB의 Java 전체 검사 | 107개 통과: 기존 팀76 + 앞서 추가한 검사17 + 수정 검사14 | `java-green-result.json`, `java-green.log` |
| 원래 Spring Boot 구성을 사용한 격리 실제 HTTP | 12항목 통과: 수정, 원래 저장,401/403/400/409, 한도, 실패 후 원본, 양쪽 날짜 통계 | `http-result.json` |
| Postman 로컬 읽기 검증 | 요청2·assertion8개 통과, exit0 | `postman.log` |
| Android 실제 API | 8항목: 기존 값, 취소, 날짜/분 변경, 같은 ID, 이전 날짜 제외, 새 날짜 합계, 통계 갱신, 재진입 | `android-result.json`, `android-drive.log` |
| 일반 앱 APK | main.dart로 debug 빌드·설치. 테스트 진입점/임시 계정 표식 미포함 | `apk-result.json`, `apk-build.log` |
| 일반 앱 실행 | 핫 리로드 성공, 런타임 오류 없음 | `runtime-result.json` |
| 실제 개발 서버8080 | 수정 전 서버를 확인해 같은 팀 서버만 재시작, OpenAPI에서 PATCH 반영 확인 | `server-result.json` |

쓰기 검사는 별도 임시 DB/합성 SAMPLE 계정에서만 했다. 실제 개발 DB에 테스트 기록을 만들거나 수정하지 않았다. 격리 서버/DB와 임시 로그인 설정은 검사 후 종료/제거했다.

개발 서버를 재시작할 때 기존 실행 스크립트를 사용했다. DB 초기화는 `never`, 기본 생성 보안 암호가 로그에 나오지 않도록 해당 프레임워크 로그만 제한한 프로세스 환경을 사용했으며 원래 설정 파일은 변경하지 않았다. 기존 운영 계정으로 수정하는 검사는 하지 않았다.

설치된 Postman1.75.0은 `status` 명령을 지원하지 않았다(`postman-status.log`). 컬렉션 실행은 로컬에서 성공했다. CLI의 클라우드 로그인 안내가 출력되었으나 로그인·업데이트·게시를 하지 않았다. 보고 이벤트를 끄고 비밀 환경 파일은 임시 폴더에서만 사용했다.

## 모의·화면 검사

- `flutter test --no-pub --reporter expanded`: **141개 통과**. 기존124 + 신규 수정 검사17. `flutter-all.log`.
- `flutter analyze --no-pub`: **문제 없음**. `analyze.log`.
- 수정 진입 부재와 서버404를 먼저 실패로 확인했다(`flutter-red.log`, `java-red-result.json`).
- 400/409 입력 보존, 이중 탭 PATCH1회, 취소, 응답 유실, 잘못된 응답 ID,403 후 데이터 숨김, 기간 밖 날짜 이동을 확인했다.
- 320/360/412 너비 × 글자150%/200%, 키보드 하단300 높이에서 수정 입력·검증·취소를 확인했다.
- 독립 검토에서 ‘수정한 낮은 ID가 다음 페이지에 있는데 확인 완료가 열리는 경우’를 찾았다. 21개 기록으로 실패를 재현하고 수정 후 통과했다(`pagination-red.log`, `flutter-feature.log`).
- 실제 TalkBack 음성, 물리 휴대폰, 앱 강제 종료 후 불확실성 복원, release 배포는 미검증이다. 계정·보안 저장소 코드는 변경하지 않았다.

## 실제 화면 · 모두 격리 API의 합성 데이터

60분 기록을 전날75분으로 정정했다. 기록 개수와 ID는 유지되었고 주간 합계는160분에서175분으로, 이전 날짜는0분·대상 날짜는기존30분+75분=105분으로 바뀌었다.

| 수정 전 | 입력 | 수정 후 | 개인 통계 |
| --- | --- | --- | --- |
| ![수정 전 목록](<C:/Users/std66/Documents/ChatGPT/PASS_FACE _ TEST/passpace_mobile/docs/study-edit/screenshots/live-edit-before.png>) | ![날짜와 시간 수정](<C:/Users/std66/Documents/ChatGPT/PASS_FACE _ TEST/passpace_mobile/docs/study-edit/screenshots/live-edit-input.png>) | ![수정 후 목록](<C:/Users/std66/Documents/ChatGPT/PASS_FACE _ TEST/passpace_mobile/docs/study-edit/screenshots/live-edit-after.png>) | ![수정 후 통계](<C:/Users/std66/Documents/ChatGPT/PASS_FACE _ TEST/passpace_mobile/docs/study-edit/screenshots/live-edit-statistics.png>) |

## 파일 범위

팀 프로젝트 변경은 아래 기존6개뿐이다. 별도 Controller/Service/테이블을 추가하지 않았다.

`C:/Users/std66/passpace11144/src/main/java/com/passpace/study/`

- `StudyController.java`: PATCH 요청과 인증 주체 전달
- `StudyService.java`: 수정 인터페이스
- `StudyServiceImpl.java`: 소유권·잠금·기존 값 비교·시간 한도·수정 응답
- `StudyRepository.java`: 본인 기록 잠금/수정 인터페이스
- `JdbcStudyRepository.java`: 본인 조건과 원래 값 조건의 UPDATE, 두 열만 수정
- `StudyDtos.java`: 네 필드의 엄격한 요청 계약

앱 운영 코드 변경은 `lib/data/api.dart`, `lib/ui/study_record_form.dart`, `lib/ui/study_records.dart`다. 나머지는 앱의 테스트·격리 검증 스크립트·문서·API 산출물이다. 기존 모델/세션/보안 저장소/의존성/Gradle/Manifest/실행 스크립트는 유지했다. 전체 파일 해시 비교는 `scope-result.json`에 기록한다. 팀의 기존 테스트 파일도 수정하지 않고 검사는 앱 보관본을 격리 복사본에 주입했다.

원래 React/쿠키 인증 서비스의 루트 API 문서/생성기와 루트 Java/React 실행 검사는 이번 팀 앱 변경 대상이 아니다. 앱 아래의 `docs/api-contract.md`, `scripts/generate-api-artifacts.py`, OpenAPI/읽기 전용 Postman 컬렉션을 함께 관리한다.

## 갱신

- 새 debug APK: `C:/Users/std66/Documents/ChatGPT/PASS_FACE _ TEST/passpace_mobile/build/app/outputs/flutter-apk/app-debug.apk`.
- 에뮬레이터는 갱신·실행했고 핫 리로드까지 확인했다. 휴대폰은 이 APK로 업데이트한다.
- 실제 팀 서버8080도 새 코드로 재시작했다. 다음 실행부터 기존 `서버 켜기.cmd`를 그대로 사용한다.
- 서버를 사용할 동안 PC/서버/DB가 실행 중이어야 한다. 외부 공유 서버를 새로 배포한 작업은 아니다.

## 검토

전체 Java6개·Dart3개와 기존 인증/소유권/계약을 읽기 전용 독립 검토했다. 발견한 페이지 확인 문제를 실패→수정→통과로 검증한 뒤 해결 확인을 받았다. 검토자는 직접 테스트/빌드를 실행하지 않았으며 실행 증거는 위 로그다.
