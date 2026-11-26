# PASS PACE 1122jhg 확장 API

기존 Bearer JWT와 `status`·`code`·`data` 응답 형식을 사용한다. 날짜는 서울 기준 `YYYY-MM-DD`, 공부시간은 정수 분이다.

| 방식 | 주소 | 입력 | 성공 응답 data |
| --- | --- | --- | --- |
| PATCH | `/api/chat/planner/review-based/plans/{planId}/tasks/{taskId}` | `expectedPlanVersion` 필수, `scheduledDate`와 `estimatedMinutes` 중 하나 이상 | `planId`, `taskId`, `planVersion`, `scheduledDate`, `estimatedMinutes` |
| PATCH | `/api/chat/planner/review-based/plans/{planId}/period` | `expectedPlanVersion`, `startDate`, `endDate` | `planId`, `planVersion`, `startDate`, `endDate` |
| GET | `/api/chat/planner/review-based/plans/{planId}/schedule` | 본인의 활성 계획 ID | 일정 입력·서버의 오늘 날짜·요일별 최대 시간·기존 과목별 수정 가능 시간·보존 항목 수 |
| POST | `/api/chat/planner/review-based/plans/{planId}/schedule/preview` | `expectedPlanVersion`, `startDate`, `endDate`, `weekdayMinutes`, `subjects` | `approval`, `changed`, `protectedTasks`, 날짜·과목별 `removed`, `added` |
| PATCH | `/api/chat/planner/review-based/plans/{planId}/schedule` | 미리보기 요청과 같은 값 및 응답의 `approval` | 같은 `planId`, 갱신된 `planVersion`, `startDate`, `endDate` |
| DELETE | `/users/me` | `password`, `confirmation`, `deletePersonalData: true` | `withdrawn: true`, `personalDataDeleted: true` |

전체 수정에서 `weekdayMinutes`는 월요일 1부터 일요일 7까지의 요일 번호와 1~960분의 매핑이다. 예전 계획에 요일 설정이 없으면 빈 맵을 돌려준다. `subjects`는 조회한 과목을 모두 포함한 `[{key, minutes}]`이고, 0분은 남은 일정에서 해당 과목을 재배정하지 않는다는 뜻이다. 기존 과목의 앞으로 배정할 분만 다룬다. 지난 날짜, 이동이 기록된 항목, 공부기록과 연결된 항목은 식별자와 배정값을 유지한다. 일정이 완전히 같은 항목의 식별자도 유지한다.

서버가 날짜순으로 설정한 요일의 가용 시간에서 보존 항목의 시간을 뺀 뒤 남은 과목을 배정한다. 기간이 보존 항목을 제외하거나 시간이 부족하면 400을 반환한다. 저장 시 회원·계획의 소유권, 세션의 전공, 계획 버전과 미리보기 서명을 검증하고 사용자 잠금 안에서 한 트랜잭션으로 반영한다. 다른 변경이나 새 공부기록으로 미리보기가 달라졌으면 409를 반환한다.

계획 항목 변경은 사용 중이거나 보관된 본인 계획에 적용한다. 기존 계획의 시작일과 종료일 안에서 오늘 이후 날짜, 항목당 1~960분, 하루 총 960분까지 입력한다. 과거 항목과 해당 날짜의 실제 기록으로 배정 시간을 채운 항목은 보호한다. 실제 기록은 원래 날짜와 항목 연결을 유지한다. 다른 기기에서 계획을 먼저 수정했으면 409로 응답한다. 기존 저장된 계획 조회의 `tasks` 객체는 기존 필드에 `taskId`를 추가한다.

계획 기간을 변경해도 개별 날짜·배정시간은 유지된다. 이미 배정된 날짜를 벗어나는 기간은 저장할 수 없다. 과거 시작일은 기존 값 그대로 유지할 수 있으며 새 날짜는 오늘부터 540일 이내다. 기간을 늘린 후 넓어진 범위로 항목을 옮길 수 있다.

회원탈퇴 확인 문구는 로그인 아이디 뒤에 `회원탈퇴`를 붙인 값이다. 계정과 본인의 계획·기록·목표·대화·AI 제안을 한 트랜잭션에서 삭제한다. 실패하면 전체를 되돌리며, 탈퇴한 계정의 기존 토큰은 보호 API에서 거부된다.

테스트 예시는 격리된 SAMPLE 계정과 DB에서만 실행한다.
