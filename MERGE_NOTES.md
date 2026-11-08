# 패스페이스 병합본 (2차, 2026-11-08)

## 1. 구성

| 영역 | 출처 | 비고 |
|---|---|---|
| 공통 (`common/`, `global/`, `PasspaceApplication`, `build.gradle`) | 완성본 | 팀원 제출본과 내용 동일 확인 |
| 한결 (`user/`, `home.html`, `fragments/layout.html`, `user/*.html`, `app.css`) | `pass_web\sample\passpace-한결-전달용` | 그대로 |
| 동건 (`chat/`, `fake/`, `prompts/`, `chatbot.js·css·html`, 테스트 5개) | `pass_web\sample\passpace-chat-1107` | 아래 2번 수정 5곳 |
| 용성 (`collect/`, `collect/admin.html`, `resources/collect/`) | **완성본 코드 (임시)** | 용성 제출 후 이 폴더들만 교체 |
| DB 스크립트 `db/01~04` | 완성본 | DB 이름만 `passpace_merged` 로 변경 |

빠진 것 (의도적으로 제외): 각자의 `dev/` 폴더, `templates/dev/`, `db/dev/`, 임시(STUB) 화면, `application-local.yml`, `build/`, `.gradle/`

> **2026-11-08 21:37 동건 영역 원본 복구** — 아래 2번·2-1번의 동건 코드 수정(ChatServiceImpl, RegexConditionParser, ChatRepository, JdbcChatRepository, MultiGoalPlannerController, chatbot.js, StudyHoursByMajorTest)을 모두 되돌려 `passpace-chat-1107` 원본과 같게 했다. `ReferenceHoursResolver.java` 는 삭제 대상. 아래 표는 기록용으로 남긴다. 복구 전 상태: `C:\dev\passpace-merged_backup_20261108.zip`

## 2. 병합하면서 고친 곳 (동건 코드, `[병합 수정]` 주석으로 표시)

| 파일 | 수정 | 이유 |
|---|---|---|
| `ChatServiceImpl` | 통합 플래너는 **SQLD 를 함께 말하거나 "통합·플래너·여러 자격증"** 을 요청할 때만 연다 | 정보처리기사 단일 계획 질문이 모두 플래너로 빠져 후기 통계·LLM 답변(핵심 기능)이 실행되지 않았음 |
| `ChatServiceImpl`, `MultiGoalPlannerController`, `JdbcChatRepository` | 대화 역할 값 `USER` / `ASSISTANT` 대문자로 통일 | 완성본·기획과 같은 값 |
| `RegexConditionParser.isPlanQuestion` | "하루 2시간", "3월 20일" 처럼 조건만 답해도 계획 질문 | 챗봇이 되물은 뒤 답하면 일반 안내가 나오던 문제 |
| `RegexConditionParser.major` | "관련 전공", "복수 전공" 띄어쓰기 허용 → RELATED | "관련 전공이에요" 가 전공자로 읽히던 문제 |
| `RegexConditionParser.mentionsDate` | "한 달 남았어요" 를 날짜 단서로 인정 | LLM 날짜 추출이 호출되지 않던 문제 |

통합 플래너의 과목별 시간은 공개 후기 소수 사례 기반 추정치이며, 화면에 "실측 평균 아님" 으로 이미 표시된다 (그대로 유지).


## 2-1. 2차 리빌딩: 동건 통합 플래너 승인 + 기획안 3장 데이터 원칙 적용

동건의 통합 플래너를 **기획안 3.2~3.4 의 1차 구현**으로 승인하고, 코드에 고정돼 있던 임시값을 **DB 우선 → 없을 때만 잠정값** 구조로 바꿨다.

| 항목 | 1차 병합 | 2차 (지금) | 실측값으로 바뀌는 조건 |
|---|---|---|---|
| SQLD 자격증·과목 | 동건 코드 내부 목록 | `03_seed` 에 등록 (CERTIFICATIONS 2, 과목 6·7) | — (이미 DB) |
| 정처기 2027 필기 과목 | 임시 목록 (DB ID 미사용) | DB 과목 ID 1~4 사용 | — |
| 시험 목표일 | 2026 일정을 옮긴 가상값 | **EXAM_ROUNDS(용성 수집) 우선** → 없으면 가상값 + 경고 | 정처기: 용성 API 수집 시 바로. 샘플 일정이면 "샘플" 경고. SQLD: 공공 API 에 없음 → 용성이 SQLD 일정 수집을 추가해야 함 |
| 과목별 기준시간 | 블로그 1~2건 값을 코드에 고정 | `STUDY_REFERENCE_STATS` (PROVISIONAL 행) | 용성 후기 중 **합격·유효 표본 10건 이상**이면 VERIFIED 행이 생겨 자동 우선 사용 (전공 집단별 → 부족하면 전공 전체) |
| 과목별 비율 | 잠정 | 잠정 (실측 총시간 × 잠정 비율) | 후기에 과목별 시간이 거의 없어 당분간 유지. 용성 추출기가 과목별 시간을 뽑으면 교체 가능 |
| 하루 공부시간 | USER_GOALS 직접 조회 | 한결 계약 `UserStudyProfileQuery` | — |
| 컨트롤러 SQL | JdbcTemplate 직접 | `ChatRepository` 로 이동 | — |

**새 공통 계약** `common/reference/StudyReferenceQuery` (제공: 용성 `JdbcStudyReferenceQuery`, 사용: 동건 `ReferenceHoursResolver`)

**용성 영역 추가** (용성 최종본 합칠 때 이 파일들을 유지하거나 용성 코드에 반영)
- `collect/stats/ReferenceMath.java` (계산 규칙, 테스트 `ReferenceMathTest`)
- `collect/stats/JdbcStudyReferenceQuery.java`, `collect/stats/StudyReferenceAggregator.java`
- `CollectAdminController`: 후기 수집 후 자동 집계 + `POST /admin/collect/reference-stats`, `admin.html` 3번 버튼
- 집계 대상: 실제 수집 후기만 (DUMMY·SAMPLE 출처 제외), `VALID`, 합격(`pass_yn='Y'`). 시간 = `total_hours`, 없으면 준비일수×하루시간

**DB 변경** `02_schema_ext.sql` 에 STUDY_REFERENCE_STATS 확장 컬럼(과목·전공·상태·근거·키) 추가, `03_seed.sql` 에 SQLD·잠정값 10행 추가
→ **passpace_merged DB 를 01 → 02 → 03 으로 다시 만들어야 한다** (03 은 고정 ID 라 덮어 실행 불가)

**검증 (이 환경)**
- MariaDB: 새 스크립트 실행, 앱 SQL 46개 정상
- 교체 시나리오 (실제 SQL 로 실행): 초기 잠정 → 더미 48건은 제외 확인 → 크롤링 후기 15건(비전공 12·전공 3) 도착 시 비전공 실측·전공은 전체 실측으로 대체 → 4건 제외 후 비전공은 다시 전체 실측 → 후기 삭제 시 잠정값 복귀
- 동건 쪽 `ReferenceHoursResolver` 9개, 플래너 컨트롤러 13개 시나리오 통과 (브라우저가 보낸 시간 무시, 비로그인 401 포함)
- 미확인: Spring 전체 빌드·`gradlew test` (PC 에서 실행 필요)

## 2-2. 3차: 용성 후기 수집기 (velog + 티스토리 자동 탐색, 기획안 7.1 준수)

결정 사항: 출처 velog + 티스토리 / URL 은 프로그램이 자동 탐색 / 근거는 원문 문장 대신 Java 요약문 / 작성자는 해시만 저장

| 정책 (기획안 7.1) | 구현 위치 |
|---|---|
| 사이트별 약관·robots·AI 활용 확인 | `DATA_SOURCES.permission_checked_at` 이 비어 있으면 그 사이트 전체 건너뜀 (`discover/SourcePermissions`). velog=2026-11-03, 티스토리=NULL |
| 공개 글만, 목록은 사람이 고름 | `resources/collect/review_discovery_sources.txt` 의 목록·피드에서 **1단계만** 링크 추출, 실행당 최대 20건 (`review-max-per-run`) |
| robots.txt | 목록·글 모든 요청 전에 확인 (`client/RobotsRules`: 전용 봇 묶음 우선, Allow/Disallow 최장 일치, `*`·`$`) |
| 요청 간격·차단 | velog 1.5초·티스토리 0.5초(사이트별, Crawl-delay 가 더 크면 그 값), 403·429 즉시 중단, 404·로그인·robots 금지 글은 재요청 안 함 |
| 대상 자격증만 | 목록 제목 키워드 1차 + 글 내용 `extract/CertificateDetector` 2차 (정처기=1320, SQLD, 산업기사·동시 언급 제외) |
| 최근 3년·작성일 | 작성일(메타·JSON-LD·RSS) 없으면 제외, 3년 초과 제외 → `PASS_REVIEWS.posted_at` 저장 |
| 광고·협찬, 무단 전재 금지 | 광고는 기존 규칙, "무단 전재·불펌 금지" 글은 값 없이 URL·사유만 EXCLUDED 로 기록 |
| 일정 대조 | 응시 연도 > 작성 연도, 공식 시험일 이전 작성 합격 후기 → 날짜 모순 제외 |
| 댓글 혼입 방지 | 사이트별 본문 선택자 + 댓글·추천글 영역 제거 후 추출 (`discover/PostPageParser`) |
| 원문·작성자 저장 금지 | 원문 대신 요약문(`extract/ReviewSummary`), 아이디 대신 SHA-256 해시(`author_hash`, salt 는 local yml) |
| 같은 작성자 = 1표본 | `JdbcReviewStatsQuery`(챗봇 통계)·`StudyReferenceAggregator`(플래너 기준시간) 모두 작성자당 최신 1건 + 최근 3년 |

동건 연결: 후기 → `PASS_REVIEWS`(cert 1/2, exam_type, major, 시간 3종 분리) → 챗봇 통계(`ReviewStatsQuery`) / 기준시간 집계(10건 이상이면 VERIFIED) → 플래너. SQLD 후기는 cert 2·WRITTEN 으로 저장되어 SQLD 잠정값도 실측으로 바뀔 수 있다.

관리 화면 `/admin/collect` 2번: ① 탐색만(글 페이지 안 가져옴) ② 수집 실행 ③ 글 1개 미리보기(저장 안 함)

검증(샌드박스): 정책·탐색·추출·서비스 흐름 78개 확인(가짜 fetcher + fixture HTML), MariaDB 에서 작성자 중복·3년 SQL 확인(14행 → 11표본).
미확인: 실제 velog·티스토리 화면 구조 (샌드박스에서 접속 불가) → PC 에서 ①·③ 으로 확인 필요.

## 2-3. 4차: 수집 속도·관리자 기능 (용성 영역만, DB 변경 없음)

| 항목 | 내용 | 파일 |
|---|---|---|
| 요청 간격 사이트별 | velog 1.5초·45초 대기 유지, 티스토리(블로그 전체를 한 사이트로) 0.5초·20초 대기. robots.txt Crawl-delay 가 더 크면 그 값 | ReviewPageFetcher, RobotsRules, application.yml |
| 동시 수집 | velog·티스토리 작업자 1개씩 동시 실행 (사이트 안에서는 한 건씩) | ReviewCollectServiceImpl |
| 중복 요청 제거 | 목록은 실행당 1번, robots.txt 는 24시간 재사용 | 같음 |
| 3년 지난 글 미리 제외 | 목록에 작성일이 있는 글만(velog 목록). 제목 필터는 그대로 | 같음 |
| 건수 지정 · 백그라운드 | 관리자 화면에서 10~1000건·사이트 선택, 진행률·중단, 끝나면 참고 학습시간 자동 집계 | CollectAdminController, admin.html, CollectDtos |
| 관리자 비밀번호 | `/admin/**` 는 `passpace.admin.password`(application-local.yml) 입력 세션만. 비어 있으면 잠금 | collect/web/*, admin_login.html |
| 크롤링 후기 초기화 | 관리자 화면 버튼 1개. velog(3)·티스토리(7) 출처 후기만 삭제(VALID 포함), 더미(4)·시험일정·회원 데이터 유지. 삭제 예정 건수 확인 → "초기화" 입력 시 실행, 메모리의 '대상 아님' 기록 비움, 참고 학습시간 재집계, 수집 중 실행 불가 | PassReviewRepository, ReviewCollectServiceImpl, CollectAdminController, admin.html |
| 수집 이력·복구 | 찾은 글 주소·판정을 `collect-data/review_url_ledger.tsv`(본문 없음)에 계속 기록. 초기화 직전 상태는 `reset_snapshot.tsv`. 관리자 화면 "복구 수집"(이력의 저장했던 글만)·"실패분 다시 시도"·"복구율 확인"(복구율·VALID 복구율·값 일치율·못 살린 이유) | collect/ledger/*, ReviewCollectServiceImpl, CollectAdminController |
| 수집 범위 관리 | 기준점을 `collect-data/review_discovery_sources.txt`(목록: velog 태그·검색, 티스토리 RSS)·`review_seed_urls.txt`(글 주소)로 옮김(첫 실행 때 기본 파일 복사 + velog 검색어 37개 추가). 관리자 화면 velog·티스토리 탭(같은 구성): 추가·목록·검색·삭제, velog 검색어·태그와 티스토리 RSS 는 "찾은 글 보기"(새 글/저장됨), 글 주소는 "미리보기". 재시작 없이 반영 | collect/ledger/SourceRegistry, CollectAdminController, admin.html |
| 티스토리 RSS 확장 | 수집 시 선택하면 아는 티스토리 블로그의 /rss 를 읽어 같은 블로그의 다른 후기 글을 후보에 추가(블로그당 24시간 1회, 최대 400개). velog 는 검색 화면을 읽을 수 있고 티스토리 검색은 스크립트·내부 API 라 읽지 않는 차이 때문 | ReviewCollectServiceImpl |
| 수집 파이프라인 (5차) | 누르자마자 이미 아는 글(글 주소·수집 이력)부터 수집, velog 목록·티스토리 RSS 는 사이트별 스레드에서 동시에 읽어 찾는 대로 대기열에 추가. 목록 결과 1시간 저장, 목록 5xx 는 1번만 재시도, 화면에 "지금: 후보 찾는 중 (velog n/m · RSS n/m) + 글 수집 중" 표시 | ReviewCollectServiceImpl, ReviewPageFetcher, admin.html |
| DB 점검 | 관리자 화면 0번: 연결 성공/실패, DB 이름·버전, 테이블별 행 수, 빈 테이블 목록 (비밀번호·주소는 표시 안 함) | DbStatusChecker |
| 화면 정리 | 각 영역·결과칸 열고 닫기, 모두 열기/닫기 | admin.html |
| 티스토리 검색 (8차) | `www.tistory.com/search` 를 PC 크롬(Selenium, 화면 없이)으로 열어 글 주소·제목·작성일만 추출 → 기존 필터·수집기로. robots.txt 없음(404)=제한 없음, 카카오 통합약관 제12조 검토, 내부 API 직접 호출 안 함, 화면 간격 5초·검색어당 5쪽·6시간 재검색 금지, UA 에 봇 이름. 검색어는 `collect-data/tistory_search_keywords.txt`(관리자 화면 티스토리 탭). **build.gradle 에 selenium-java 추가 → 팀원 Gradle 새로고침 필요** | TistorySearchBrowser, SourceRegistry, ReviewCollectServiceImpl, admin.html |
| 접근 제한 대응 (7차) | 403·429 는 **그 사이트만** 중단(다른 사이트 계속). Retry-After(없으면 30분) 동안 그 사이트에 요청하지 않음(COOLDOWN). velog 간격 1.5초 → 3초 | ReviewPageFetcher, ReviewCollectServiceImpl, application.yml |
| 하루 공부시간 보강 (6차) | 범위(3~4시간→평균), 사이 말("하루에 꾸준히 2시간"), 앞말(퇴근 후·일과 후·평일 저녁), 평일/주말 분리(주간 평균), 주 단위(÷7). "~짜리·강의·시험 시간·걸려" 등 제외. 원문을 저장하지 않으므로 적용하려면 초기화 → 복구 수집 | RuleBasedReviewExtractor, DailyTimeRuleTest |
| 한글 기간 표현 | 세 달·두 주·열흘·이틀·반년·하루 세 시간 반 등. "한 달 뒤/남았/에 한 번/마다"는 제외 (이전엔 "한 달" 포함만 보고 30일) | RuleBasedReviewExtractor, KoreanPeriodAndAdminTest |

## 3. 실행 순서

1. **DB** (DBeaver, Alt+X): `db/01_schema.sql` → `02_schema_ext.sql` → `03_seed.sql` (04 실행 안 함)
   - 새 DB `passpace_merged` 가 만들어진다 (기존 `passpace` DB 는 그대로)
   - `passpace` 계정을 쓰면 한 번만: `GRANT ALL ON passpace_merged.* TO 'passpace'@'localhost';`
2. **설정**: `java_sw\passpace\src\main\resources\application-local.yml` 을 같은 위치(`passpace-merged\src\main\resources\`)로 복사
   - 그 파일에 `datasource.url` 이 있다면 `passpace_merged` 로 바꾸기
3. IntelliJ 에서 `passpace-merged` 폴더 열기 → Gradle 동기화 → `./gradlew test` → `PasspaceApplication` 실행

## 4. 통합 확인 체크리스트

| # | 할 일 | 정상 결과 |
|---|---|---|
| 1 | `./gradlew test` | 동건 테스트 5개 + 용성 테스트 통과 |
| 2 | 비로그인 `/` | 일정 카드, "챗봇은 회원 전용", 💬 열면 잠금 안내 |
| 3 | 회원가입 → 마이페이지 목표·하루 시간·과목 이해도 저장 | 저장 성공, 헤더에 닉네임 |
| 4 | 💬 "비전공자가 정보처리기사 필기 준비중이다. 시험날은 3월 20일, 하루 2.5시간. 학습계획 세워줄 수 있는지?" | **통계 기반 답변** (표본 수·조건 표시), 플래너 탭으로 빠지지 않음 |
| 5 | 💬 "3월 20일 시험 계획 세워 주세요" | 하루 시간이 **3번에서 저장한 값**으로 반영 (한결 ↔ 동건 연결 확인) |
| 6 | 💬 "그럼 하루 3시간이면?" → "실기는요?" | 앞 조건을 이어 다시 계산 |
| 7 | 💬 "정처기랑 SQLD 같이 준비하려고 하는데 계획 세워줘" | 통합 학습계획 탭 열림 |
| 8 | `/admin/collect` 에서 시험일정 수집 → 메인 새로고침 | 메인 일정 카드 갱신 (용성 ↔ 한결 연결 확인) |
| 9 | 로그아웃 후 `/mypage` | 로그인 화면으로 이동 |
| 10 | DBeaver `SELECT role, COUNT(*) FROM passpace_merged.CHAT_MESSAGES GROUP BY role;` | `USER`, `ASSISTANT` 만 |
| 11 | 💬 "정처기랑 SQLD 같이…" → 통합 계획 카드의 "기준시간 근거" | 정처기·SQLD 모두 "공개 원문 n건 (50명 실측 평균 아님)" = 잠정값 (후기 10건 미만) |
| 12 | `/admin/collect` → 3번 "참고 학습시간 다시 집계" | 더미만 있으면 결과 비어 있음/표본 부족 → 잠정값 유지 (정상) |
| 13 | `/admin/collect` → 2번 ① 탐색만 해 보기 | velog 태그 목록별 "링크 n개 중 후기 후보 m개", 티스토리는 "아직 확인하지 않았습니다" |
| 14 | 13 에서 나온 주소 하나로 ③ 미리보기 | `verdict` SAVE_VALID/EXCLUDED/PENDING, `postedAt` 날짜, `review.evidenceText` 요약문 |
| 15 | ② 후기 수집 실행 → DBeaver `SELECT source_id, certification_id, posted_at, LEFT(author_hash,8), review_status, exclude_reason, evidence_text FROM PASS_REVIEWS WHERE source_id IN (3,7);` | 원문 문장·아이디 없음, 작성일·해시 있음 |

## 5. 남은 일
- 용성 최종본 도착 → `collect/`, `templates/collect/`, `resources/collect/`, `src/test/java/com/passpace/collect/` 교체 후 4번 다시 확인
- 한결 코드에 남은 `// TODO(한결): 구현` 주석 정리 (내용은 구현됨)
- 용성: 티스토리 약관·robots·AI 활용 확인 → `UPDATE DATA_SOURCES SET permission_checked_at = NOW() WHERE source_id = 7;` + 블로그 RSS 주소 추가
- 용성: velog 태그 목록에서 후보가 0개면(화면을 JS 로 그리는 경우) 작성자 RSS(`https://v2.velog.io/rss/@아이디`)로 바꾸기
- 용성: SQLD 시험일정 수집 추가 여부 (후기는 이제 SQLD 도 수집)
- 다음 단계: 계획 저장(STUDY_PLANS·PLAN_GOALS·STUDY_PLAN_DETAILS), 과목별 시간 추출
- 이 병합본을 GitHub `main` 의 첫 커밋으로 사용
