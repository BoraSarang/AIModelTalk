# PLAN (macOS) — T-344 README·랜딩·릴리즈·Pages·Actions (3분 초안)

## 범위 (원칙: 서명 없음, 무료·키리스 유지)
1. README 확장 — 스크린샷 자리, 설치(DMG/zip 릴리즈 + 직접 빌드), Gatekeeper 안내, 문서 링크
2. 랜딩 `site/index.html` (한국어, 단파일, 외부 의존 없음) — 기능·공급자·설치·FAQ
3. Actions `ci.yml` — macOS 러너: xcodegen → Debug 빌드 → unit 테스트 (full ≤5분 예산)
4. Actions `pages.yml` — `site/` 아티팩트 Pages 배포
5. Actions `release.yml` — 태그 `v*` 시 Release 빌드 → zip → Release 업로드
6. Pages 활성화(gh api) + `v0.1.0` 태그·릴리즈 생성

## 제외
- 공증·서명(인증서 없음 — 릴리즈 노트에 Gatekeeper 우회 안내)
- 스크린샷 실촬영(자리 표시자 + `scripts/screenshot.sh` 존재 명시)
- Homebrew cask

## 검증
- `act` 없음 → 워크플로 YAML 문법 점검 + 푸시 후 Actions 실행 확인
- Pages URL 200 확인, 릴리즈 에셋 다운로드 확인
