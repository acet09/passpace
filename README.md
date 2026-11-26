# PASS PACE

자격증 학습 계획 서비스. main 에는 서버와 앱을 폴더로 나눠 담는다.

```
passpace/ (main)
├── server/   Spring Boot 서버 (Java 21, Gradle)  ← develop 브랜치 내용
├── app/      Flutter 앱 (Android)                ← passpace-app-full 브랜치 내용
└── README.md
```

## 실행
- 서버: `cd server` 후 `gradlew bootRun` (로컬 설정 `server/src/main/resources/application-local.yml`은 각자 PC에서 관리)
- 앱: `cd app` 후 `flutter pub get` → `flutter run`
- Windows에서 서버를 한 번에 켜려면 `app/서버 켜기.cmd` (같은 저장소의 `server/`를 자동으로 찾음)
- 챗봇은 Claude API 를 쓴다. 키는 환경변수 `ANTHROPIC_API_KEY` 또는 `application-local.yml` 의 `passpace.claude.api-key` (저장소·단체방에 올리지 않음). 키가 없어도 서버는 켜지고 챗봇만 기본 안내로 답한다
- 자세한 내용은 `server/README.md`, `app/README.md`

## 브랜치 규칙
| 브랜치 | 내용 | 작업 방식 |
|---|---|---|
| `develop` | 자바 서버 | 기능 브랜치 → `develop` 으로 PR |
| `passpace-app-full` | Flutter 앱 | 기능 브랜치 → `passpace-app-full` 로 PR |
| `main` | 두 브랜치를 `server/`, `app/` 폴더로 나눠 담은 최종본 | 관리자가 두 브랜치 최신 내용을 폴더에 넣어 갱신 |

- 흐름은 한 방향만: `develop` / `passpace-app-full` → `main`
- **하지 말 것**: `main` 을 `develop`·`passpace-app-full` 로 병합하기(PR 화면의 "Update branch" 포함), 깃허브 웹에서 `develop` → `main` PR 을 바로 만들기. 두 경우 모두 폴더 구조가 섞인다
- 기능 PR 을 만들 때 base 가 `main` 으로 잡혀 있지 않은지 확인

## main 에만 있는 설정
- `server/.gitignore` 의 `collect-data/`
- `app/scripts/Start-TeamServer.ps1` 의 `(Join-Path $appParent 'server')` 한 줄 (같은 저장소의 `server/` 자동 탐색)

## 변경 기록 (자세한 내용은 각 README)
| 날짜 | 담당 | 내용 | 위치 |
|---|---|---|---|
| 11-09~10 | 팀 | 3인 코드 통합(#1~#6), 팀 DB `passpace_merged` 확정 | - |
| 11-13 | 동건 | 세션 로그인 → JWT 인증(#7), USERS.role(db/08) | - |
| 11-14 | 용성 | 후기 수집 리빌딩(크롤링 + 네이버 검색 API), 컴활 1급·ADsP 추가(db/09) (#8) | - |
| 11-14 | 팀 | 웹 → 앱(Flutter) 플랫폼 전환 결정 | - |
| 11-15~17 | 팀 | 자격증 3개 묶음 계획·상담 채팅 계획(동건), 학습기록·통계 API·Flutter 앱 공유(한결), 과목 언급 수집 db/10(용성) (#9~#12) | - |
| 11-19 | 동건 | 계획 여러 개 관리, 상담 요일·요일별 시간, 단계별 계획 카드, 재편성 추천, API 8개 추가·변경 | server 6장, app README |
| 11-20 | 용성 | 총학습량 계산 수정, 일지형 후기 합산, 과목 언급 끝까지 자동, ADsP·컴활 과목 비율(db/11) | server 6-1장 |
| 11-21 | 용성 | 네이버 후기 보충·박스플롯, 관리자 수집자료정보 페이지 | - |
| 11-22 | 동건 | 과목 비율을 수집 데이터 기준으로, 챗봇 로컬 LLM(Ollama) → Claude API | server 7장 |
| 11-23 | - | main 을 develop(#22)·passpace-app-full(#23) 최신으로 갱신 | - |
| 11-24 | 용성 | 네이버 후기 본문 재판정(유효 후기 968 → 5,634건), 새 자격증 후기 양 시험 측정 | - |
| 11-25 | 용성 | Docker + Tailscale 모의 배포 서버, 앱에서 Tailscale 서버(100.x) http 허용 | - |
| 11-26 | 한결 | 앱 13건(홈 진행률, 계획 전체 수정, 타이머, 과목 색, 통계, 회원탈퇴), API 6건(일정·기간·전체 계획 수정, 회원탈퇴) (#25, #27) | server docs/api-contract.md |
| 11-26 | 동건 | 상담 계획에서 자격증별 하루 시간 읽기 수정 (#26) | - |
| 11-26 | 용성 | 자격증 4종 → 9종, 지원 자격증 정보 메뉴·API(`/api/certifications`), db/12~15 (#28, #29) | - |
| 11-27 | 용성 | 팀 공용 Docker DB(Tailscale), 릴리스 빌드 오류 수정(network_security_config) | - |

## git 밖 로컬 데이터
- `server/collect-data/`, `server/src/main/resources/application-local.yml`
