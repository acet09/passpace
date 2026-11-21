# PASS PACE

자격증 학습 계획 서비스. 한 저장소에 서버와 앱을 폴더로 나눠 관리한다.

```
passpace/
├── server/   Spring Boot 서버 (Java 21, Gradle)
└── app/      Flutter 앱 (Android)
```

## 실행
- 서버: `cd server` 후 `gradlew bootRun` (로컬 설정 `server/src/main/resources/application-local.yml`은 각자 PC에서 관리)
- 앱: `cd app` 후 `flutter pub get` → `flutter run`
- Windows에서 서버를 한 번에 켜려면 `app/서버 켜기.cmd` (같은 저장소의 `server/`를 자동으로 찾음)
- 자세한 내용은 `server/README.md`, `app/README.md`

## 브랜치 규칙
- `main`: 최종본, `develop`: 통합 브랜치
- 기능 브랜치는 `develop`에서 만들고 PR도 `develop`으로 연다
- 서버와 앱을 함께 바꾸는 작업은 PR 하나에 `server/`, `app/` 변경을 같이 담는다

## git 밖 로컬 데이터
- `server/collect-data/`, `server/src/main/resources/application-local.yml`
