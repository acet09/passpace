# 학습기록 삭제·과목 연결 계획

사용자 승인: 기존 학습기록 Java6파일과 앱만 수정. 다른196개 팀 파일, 기존 테스트백엔드66파일, SQL/보안/버전/다른 팀원 코드는 보존. 현재 세션에서 구현·검증한다.

## 원인과 선택

기존 계획 조회의 Task에는 taskId가 없고 기존 앱은 과목 선택 없이 날짜/분만 POST했다. DB의 실제 STUDY_PLAN_DETAILS 식별자를 학습기록 패키지에서 읽어 사용한다. 이름으로 ID를 추정하거나 다른 팀원의 계획 DTO/조회 코드를 변경하지 않는다. 과목 레지스트리 ID가 null이어도 본인 계획 항목 ID와 저장된 과목명으로 연결할 수 있다.

## 계약

- 추가 `DELETE /study/sessions/{sessionId}`: expectedStudyDate/expectedDurationMinutes 필수, expectedTaskId는 기존 연결 ID(미연결 null). 직접 입력 기록만 본인/전공/사용자·기록 행 잠금/기존 날짜·분·연결 비교 뒤 삭제.200 `{sessionId,deleted:true}`. 존재하지 않음/다른 사용자403, 오래된 값409, 잘못된 값400. 계획·과목·다른 기록은 삭제하지 않는다.
- 추가 `GET /study/plan-tasks`: date 선택(생략하면 전체 일정), includeReplaced 기본false, page0..10000/pageSize1..100 기본50. 본인 ACTIVE(옵션으로REPLACED) 계획의 실제 taskId/planId/planVersion/과목명/선택적subjectId/시험명/배정일을 페이지로 제공. DRAFT/다른 사용자/버전 없는 계획 제외. 실제 시작시각이나 공부시간을 만들지 않는다.
- 기존 POST는 선택한 taskId+expectedPlanVersion을 그대로 사용한다.
- 기존 PATCH의4필수 필드는 유지한다. 선택 `taskLink:{taskId?,expectedPlanVersion?,expectedTaskId?}` 추가. 생략하면 기존 연결 유지. 객체가 있으면 기존 연결을 비교한 뒤 실제 본인 항목/버전을 검증해 연결(양수taskId) 또는 해제(taskId:null). 날짜/분과 연결을 함께 저장한다. 이전 요청 형식은 계속 동작한다.
- 새 링크 객체/삭제의 null 또는 생략 expectedTaskId는 미연결을 의미하므로 이미 연결된 기록에서는409이다. DB 버전 컬럼을 새로 만들지 않고 값 비교 방식의 한계를 문서화한다.

## 앱

- 기록의 삭제 버튼 → 날짜/과목/시간과 복구 불가 안내 → 삭제 확인. 취소·실패는 기록 유지, 성공하면 목록/통계 재조회.
- 추가/수정 화면에서 과목 선택. 선택한 날짜/전체 일정, 이전 계획 포함 필터와 페이지 제공. 현재 연결 유지/연결 없음도 명시적으로 선택 가능. 계획 배정 시간을 실제 분에 자동으로 채우지 않는다.
- 응답 유실·인증/계정 변경·동시 수정·이중 탭 보호 유지. 삭제 불명은 같은 ID가 있는지/페이지 끝까지 확인한 뒤 다른 쓰기 허용. 자동 DELETE/POST/PATCH 재전송 없음.

## 작업 파일과 검증

팀: 기존 StudyController/StudyService/StudyServiceImpl/StudyRepository/JdbcStudyRepository/StudyDtos.java만. 앱: 학습기록 데이터/API/폼/목록, 과목 선택·삭제 확인 UI, 관련 검사·검증 도구·문서. 인증/공통 모델/의존성은 유지한다.

- [x] 범위/해시 기록, 격리 프로젝트·6파일 작업본 준비.
- [x] Java에서 삭제/계획 항목 경로의 실패를 먼저 확인하고 소유권·전공·충돌·필드 보존·과목 연결·해제·통계 검증. 전체120 통과.
- [x] 앱 삭제/과목 선택 검사를 실패→구현→통과, 전체155 통과·정적 오류0. 작은 화면/큰 글자/기존 키보드/응답 유실 검사 포함.
- [x] 격리 실제 HTTP20확인/Postman12검사/Android7흐름·6화면·일반 APK·핫 리로드·런타임 오류0. 실제 계정 테스트 쓰기0.
- [x] 독립 읽기 전용 최종 검토1회, 지적0. 허용6파일만 변경, 팀 나머지196/이전백엔드66 동일.
- [x] API 목록을 기존4개+신규2개 총6개로 갱신하고 원인·사용법·실제/모의/미검증을 기록.

완료 증거: verification.md, scope-result.json, java-green-result.json, android-result.json, apk-result.json, runtime-result.json. 기존 사용자의 미커밋 변경을 보존하며 커밋/푸시하지 않았다. 격리 복사본으로 검사하고 사용자 승인 범위6파일만 적용했다.

검토 초점: 삭제 중 수정/재연결 경합, 연결만 변경된 기록의 오래된 삭제, 다른 사용자·DRAFT/버전 틀린 계획 거부, null과 생략의 하위 호환, 결과 불명/다음 페이지/계정 전환 뒤 쓰기 차단.
