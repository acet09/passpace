# 기록 탭·진행 알림·월간 달력 구현 계획

요청: 기록 탭을 누르면 타이머 바로 표시, 학습기록/통계 분리, 다른 앱/휴대폰 알림창에서도 측정 상태 확인, 홈과 계획에서 월간 확장, 하단 오늘→홈. 백엔드·다른 팀원 코드·기존 API·의존성 버전은 유지한다.

설계: 기존 학습기록 화면 상태가 타이머1개와 미확정 저장 상태를 계속 소유한다. 기본 본문은 타이머, 학습기록/통계는 각각 별도 본문으로 전환한다. 탭 재진입/재선택과 알림 누르기는 타이머로 복귀한다. 확인하지 않은 저장 결과는 기존 차단을 유지한다. 홈 달력은 주/월 전환, 계획은 월간 기본과 주간/전체목록을 제공하고 월 제목에서 기간 내 다른 날짜로 이동한다.

Android 기본 API만으로 전경 서비스를 추가한다. POST_NOTIFICATIONS 런타임 권한, ongoing/저소음 알림, 자동 경과 시간, 비공개 잠금 화면, 누르면 타이머로 이동. 일시정지·저장·초기화·로그아웃 때 종료. 특별 용도 서비스와 사용 이유를 앱 Manifest에 명시한다. 서버·계정/토큰을 네이티브 서비스에 전달하지 않는다. 소유 인스턴스 토큰과 직렬화로 이전 세션 알림이 새 알림을 지우지 않게 한다. 알림 권한 거부 시 측정은 유지하고 설정 동선을 제공한다.

직접 구현하고 마지막에 독립 읽기 전용 검토1회. 불필요한 설계 승인·배포·커밋/푸시는 진행하지 않는다. 기존 로컬 사용자 변경은 보존한다.

- [x] 범위·해시 기록/현재 소스·공식 Android 문서 확인.
- [x] 기본 타이머·분리 동선·홈 이름·주/월 달력 검사 RED→GREEN.
- [x] Android 알림/권한/딥링크와 Flutter 상태 연동, 오류·세션·수명 검사.
- [x] 기존 입력/수정/삭제/복원·큰 글자·달력 회귀 검사/정적 검사.
- [x] 실제 격리 API·Android 알림창·백그라운드·알림탭·일시정지 제거·화면 캡처. 로그아웃/소유권 전환은 모의 검증으로 구분.
- [x] 독립 검토 지적 수정·일반 APK 갱신/핫 리로드/런타임·전체 백엔드 보존 검증/문서.

변경 파일: lib/ui/dashboard.dart, study_records.dart, study_timer_screen.dart, plan_month_calendar.dart, lib/data/study_timer.dart 및 새 알림 브리지, Android MainActivity.kt(기존 관리자 핸들러 보존)·신규 서비스/알림 아이콘·Manifest 권한/서비스 선언, 관련 검사와 검증 문서. pubspec/Gradle/서버/인증/API/기존 저장 키는 변경하지 않는다.

공식 근거: Android 알림 권한(https://developer.android.com/develop/ui/views/notifications/notification-permission), specialUse(https://developer.android.com/develop/background-work/services/fgs/service-types#special-use), 자동 시간 표시(https://developer.android.com/reference/android/app/Notification.Builder#setUsesChronometer(boolean)). Play 배포용 특별 용도 심사와 OEM별 백그라운드 차이는 별도 검증 사항이며 이번 로컬 APK 확인과 구분한다.

완료 증거: Flutter195개·정적 검사 통과, 실제 격리 Android9개 흐름/네이티브5개 확인/10장 캡처, 실제 기존 HTTP12개·Postman8검사. 독립 검토1회에서 Important2개·Minor2개를 수정했으며 재검토 요청 없이 회귀 검사와 실행으로 확인했다. 상세 구분은 verification.md에 기록한다. 일반 APK 설치·핫 리로드 성공/런타임 오류0. 팀202개·이전 백엔드66개 변경0, 기존 MainActivity 관리자 핸들러 보존.
