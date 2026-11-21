# 달력 선택 문구 · 관리자 페이지 연결

2026-11-15. 달력의 시각적인 선택 글자를 제거하고 파란 강조·접근성 선택 상태를 유지했다. 내 정보에는 관리자 계정에만 관리자 페이지 메뉴를 추가했다.

[전후 화면·관리자 메뉴](index.html) · [변경 파일 해시](scope-verification.json)

## 사용 흐름

관리자 계정으로 로그인 → 내 정보 → 관리자 페이지. 현재 앱 서버의 기존 웹 /admin/collect를 브라우저로 연다. 웹과 앱 로그인은 별도이므로 브라우저에서 관리자 로그인이 필요할 수 있다. 권한을 변경한 계정은 기존 서버 방식대로 다시 로그인해 새 권한 토큰을 받는다.

앱 토큰·비밀번호를 URL·브라우저에 전달하지 않는다. 기존 웹과 같은 JWT role=ADMIN을 메뉴 표시용으로 읽고, 실제 인증·관리자 작업 허용 여부는 기존 서버가 판단한다. 계정 권한을 만들거나 바꾸지 않았다.

## 수정 파일

| 파일 | 변경 |
| --- | --- |
| lib/ui/plan_month_calendar.dart | 선택 문구를 제거했다. 선택 날짜도 배정·오늘·빈 날짜 표시를 사용하며 파란 배경과 접근성 selected는 그대로다. |
| lib/ui/auth.dart | 내 정보에 관리자 조건부 메뉴를 추가했다. 로그인·가입·연결 설정 코드는 동일하다. |
| lib/ui/admin_link.dart | 표시용 관리자 판별, 브라우저 열기 요청·오류·중복 탭 처리를 담당한다. API나 세션 저장을 변경하지 않는다. |
| android/app/src/main/kotlin/kr/passpace/mobile/passpace_mobile/MainActivity.kt | 앱에서 브라우저를 여는 화면 연결이다. 정확한 관리자 경로와 허용된 웹 주소만 받으며, 인증 정보·쿼리·프래그먼트가 있는 주소는 거부한다. |
| test/admin_entry_test.dart, test/plan_month_calendar_test.dart | 관리자/일반·만료·잘못된 토큰·계정 불일치, 320/360/412와 200% 글자, 토큰 없는 URL, 실행 실패, 달력 강조·접근성 유지를 검사한다. |
| integration_test/admin_entry_test.dart | 가상 관리자 프로필과 실제 메뉴 탭 → 실제 Kotlin 연결 → 브라우저 실행, 잘못된 주소 거부를 확인한다. |
| docs/admin-entry, docs/verification.md, docs/backend-integrity.json | 결과 화면·수정 이유·실제/모의/미검증과 무결성을 기록한다. |

Android의 기존 SDK만 사용했다. 새 패키지·Manifest 권한·환경 버전은 추가하지 않았다. URL 열기와 처리 앱이 없을 때의 예외 처리는 [Android 공식 안내](https://developer.android.com/training/package-visibility/use-cases#open-urls)를 참고했다.

## 실제 실행 검증

- Android에서 실제 관리자 메뉴 탭이 Kotlin의 브라우저 연결에 전달되고 성공 응답을 받는 것을 확인했다. 잘못된 스킴·경로·사용자 정보·쿼리·외부 HTTP 주소는 거부됐다. 기본 브라우저가 전면에 열린 것도 확인했다.
- 일반 lib/main.dart APK 빌드·설치 후 기존 로그인 복원과 대시보드 진입을 확인했다. 핫 리로드 성공, 전후 Dart 런타임 오류 0건이다.
- APK 안에 관리자 UI와 실제 Android 연결 코드가 포함되고 테스트 진입점은 제외됐다.
- 기존 Android 보안 저장소의 키 읽기 경고는 남아 있으나 대시보드는 정상 진입했다. 저장소·계정 데이터를 초기화하지 않았다.

## 모의 검증

- 단위·화면 테스트 65개와 정적 검사 통과. 관리자 메뉴 부재와 달력 선택 문구 존재로 먼저 실패한 테스트를 구현 후 통과시켰다.
- Android UI 시나리오 2개가 통과했다. 계정·학습 데이터는 MockClient와 메모리 저장소만 사용한 SAMPLE이며 실제 서버 계정 저장소를 읽거나 쓰지 않았다. 메뉴 탭 검사에서는 관찰한 메시지를 변경 없이 실제 네이티브 연결로 전달했다.
- 이미지의 계정과 계획도 SAMPLE 가상 데이터다. 브라우저에는 공개 관리자 페이지 주소만 전달했다. 실제 관리자 로그인·수집 시작·데이터 수정·삭제는 실행하지 않았다.

## 백엔드와 보호 범위

팀 소스·SQL·설정 205개는 작업 전후 SHA-256이 동일하고 Git 변경도 없다. API·모델·세션·보안 저장소·의존성·환경·Manifest도 그대로다. 다른 팀원 코드는 수정하지 않았다.

앱 보호 파일 55개 중 모바일 화면 연결인 MainActivity.kt 한 곳만 의도적으로 변경했고 나머지 54개는 동일하다. 다른 화면 파일 9개와 로그인·가입·서버 연결 코드도 동일하다. 이 Kotlin 파일은 휴대폰 앱 코드이며 Java/Spring Boot 백엔드 파일이 아니다.

## 갱신과 미검증

에뮬레이터에는 새 일반 APK를 적용했다. 휴대폰은 [새 APK](../../build/app/outputs/flutter-apk/app-debug.apk)를 업데이트 설치한다.

전체 경로: C:/Users/std66/Documents/ChatGPT/PASS_FACE _ TEST/passpace_mobile/build/app/outputs/flutter-apk/app-debug.apk

Android 연결 코드가 추가됐으므로 개발 중에는 일반 핫 리로드만으로 반영되지 않으며 새 APK 실행이 필요하다. 개인 휴대폰·사용자 실제 관리자 계정의 웹 로그인·관리자 수집/변경 작업·실제 TalkBack과 모든 OS 조합은 미검증이다. 백엔드 변경이 필요한 새 기능은 없다.
