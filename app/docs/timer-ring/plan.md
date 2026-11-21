# 과목별 배정 시간 타이머 원형 표시 Implementation Plan

> **For agentic workers:** 현재 세션에서 superpowers:executing-plans 방식으로 직접 수행한다. 마지막에 독립 읽기 전용 검토1회. 커밋/배포/별도 승인 없음.

**Goal:** 타이머 시간 둘레의 큰 원이 선택 과목·측정 날짜의 배정 시간에 따라 채워진다. 과목 선택은 현재 ACTIVE 계획만 제공한다.
**Architecture:** 새 lib/ui/study_timer_progress.dart가 기존 saved()/studyPlanTasks() 읽기 API의 계획 ID·버전·과목/시험을 확인해 날짜별 배정 합계와 측정 경과 비율을 표시한다. StudyTimer/저장/알림/데이터 모델은 수정하지 않는다. 과목/날짜/화면 복귀 때만 다시 읽는다. 선택 없음·배정 없음·조회 오류·교체된 계획·모호한 과목은 빈 원과 정확한 안내로 표현한다.
**Tech Stack:** 기존 Flutter/Dart/Material CircularProgressIndicator, 새 패키지 없음.
**Spec:** 사용자 이번 요청. 진행은 기존 저장 기록을 합친 하루 완료율이 아닌 이번 측정/배정 대비 표시이며, 배정 도달 후에도 측정·수동 저장 동작은 유지한다.

## Global Constraints

- 팀202파일·이전 백엔드66파일·Android·API 계약·데이터 모델·인증·세션·초안·측정/시간 계산·알림·패키지/환경 버전 변경 금지.
- 기존 계획의 배정 분을 읽어 표시하고 날짜/과목별 합계와 화면 비율만 계산한다. 새 일정을 배정하지 않는다.
- 계획 ID/버전과 과목 연결을 확인할 수 없으면 비율을 만들지 않는다. 빈 날을 휴식/완료로 해석하지 않는다.
- 기존 지연 응답·계정 전환·수동 저장·오류 규칙 유지. 과거 저장 기록과 복원된 연결을 임의 변경/삭제하지 않는다.
- 320/360/412·150~200% 글자·최소48dp·접근성 이름·시스템 애니메이션 줄이기 확인.

## Task 1: 원형 표시와 현재 과목

- [x] 새 test/study_timer_progress_test.dart: 같은 날짜/과목의 실제 배정 합계, 타 날짜/시험 제외, 경과0/절반/도달 초과·과목 없음·배정 없음·교체/모호함·오류/재시도·이전 응답 폐기 검사를 작성하고 미구현 실패 확인.
- [x] 같은 검사 파일에 REPLACED 항목·체크박스 없음·includeReplaced=false 확인을 포함. 별도 과목 선택 RED를 실행한 것으로 주장하지 않음.
- [x] 새 lib/ui/study_timer_progress.dart 구현. 기존 데이터 읽기만 사용, 날짜/선택/계정과 ACTIVE·계획 버전 검증, 모델을 수정하지 않는 원형 표시.
- [x] lib/ui/study_timer_screen.dart: 숫자 시간 위치에 원형 컴포넌트 연결. 기존 시간 key/측정·저장/복원/알림 유지.
- [x] lib/ui/study_task_picker.dart: 이전 계획 체크박스/조건 제거, ACTIVE만 조회/검증. 현재 과목 중복 제거 유지.
- [x] 새16개 포함 전체211개·정적 검사 통과. 첫 화면 시작 버튼은 별도 RED 후 화면 높이별 크기 조절로 통과.

## Task 2: 실행·보존

- [x] 실제 에뮬레이터의 모의 화면 결과 확인 및 일반 앱 핫 리로드/런타임 오류0. 일반 앱은 로그인 화면이며 로그인 후 실 배정 조회/장시간 측정은 미검증으로 구분.
- [x] 별도 SAMPLE 모의 API/메모리 저장소/15분 합성 측정으로30분 배정 절반 원·현재 과목만4개 확인/2장 캡처. 실 API 쓰기0.
- [x] 독립 최종 검토1회 지적 없음. 일반 lib/main.dart APK 빌드/설치, 테스트 마커6개 미포함.
- [x] scope-before.json 대비 파일 해시 비교. 앱 비대상·전체 팀202개/이전 백엔드66개 보존. README/docs/verification.md와 이 폴더에 실제/모의/미검증·전후 화면·APK 기록.

Ruling: 현재 계획은 기존 API의 ACTIVE 정의를 사용한다. 과거 기록과 복원된 과목 연결은 자동 변경하지 않고 교체된 연결에 배정 비율을 만들지 않는다. 모의 Android 초기 실패는 예시 목록 타입 오류로 재현해 검증 도구에서만 수정했다. 운영 코드 재작업·추가 재검토는 없었다.

공식 참조: https://api.flutter.dev/flutter/material/CircularProgressIndicator-class.html (0~1 determinate), https://api.flutter.dev/flutter/widgets/MediaQuery/disableAnimationsOf.html (시스템 움직임 줄이기).
