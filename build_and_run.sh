#!/bin/bash
# build_and_run.sh — AIModelTalk macOS 빌드 디스패처
# usage: ./build_and_run.sh [debug|release] [macos]

set -euo pipefail

MODE="${1:-debug}"
PLATFORM="${2:-macos}"
APP_NAME="AIModelTalk"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
INSTALL_DIR="${HOME}/Applications"
EXISTING="${INSTALL_DIR}/${APP_NAME}.app"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

kill_app() {
  if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    warn "${APP_NAME} 종료 중..."
    killall "$APP_NAME" 2>/dev/null || true
    for _ in $(seq 1 5); do
      pgrep -x "$APP_NAME" > /dev/null 2>&1 || return 0
      sleep 1
    done
    killall -9 "$APP_NAME" 2>/dev/null || true
    sleep 1
  fi
}

if [ "$PLATFORM" != "macos" ]; then
  error "지원되지 않는 플랫폼: $PLATFORM"
fi

# ── 0. 실행 중 앱 종료 ───────────────────────────────
kill_app

# ── 1. xcodegen ──────────────────────────────────────
info "1/4: xcodegen..."
cd "$PROJECT_DIR"
xcodegen generate --spec project.yml

# ── 2. 빌드 ──────────────────────────────────────────
info "2/4: xcodebuild ${MODE}..."
CONFIG="Debug"
[ "$MODE" = "release" ] && CONFIG="Release"

BASE_ARGS=(-project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" -configuration "${CONFIG}" -derivedDataPath "${BUILD_DIR}")

# 서명: 개발 인증서가 있으면 TCC(접근성/화면캡처) 허용이 재빌드 시 유지되도록 우선 사용.
# macOS 개발 서명은 프로비저닝 프로파일이 필요하며, 없으면 실패하므로 ad-hoc으로 폴백한다.
DEV_TEAM=""
DEV_TEAM=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -oE '\([A-Z0-9]{10}\)' | head -1 | tr -d '()' || true)

if [ -n "$DEV_TEAM" ]; then
  info "개발 인증서 서명 시도 (Team: ${DEV_TEAM})..."
  if xcodebuild "${BASE_ARGS[@]}" \
       CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM="${DEV_TEAM}" CODE_SIGNING_REQUIRED=YES \
       build > /tmp/amt_sign_build.log 2>&1; then
    info "개발 인증서 서명 성공"
  else
    warn "자동 서명 실패(프로비저닝 프로파일 없음) → ad-hoc 폴백"
    xcodebuild "${BASE_ARGS[@]}" \
      CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
      build 2>&1 | tail -20
  fi
else
  warn "개발 인증서 없음 → ad-hoc 폴백"
  xcodebuild "${BASE_ARGS[@]}" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
    build 2>&1 | tail -20
fi

# set -e 하에서 xcodebuild 실패를 명시 처리
APP_PATH="${BUILD_DIR}/Build/Products/${CONFIG}/${APP_NAME}.app"
[ -d "$APP_PATH" ] || error "빌드 실패: ${APP_PATH} 없음"
info "빌드 성공"

# 빌드 중 RegisterWithLaunchServices가 재시작할 수 있으므로 재종료
kill_app

# ── 3. 설치 ──────────────────────────────────────────
info "3/4: ~/Applications에 설치 중..."
mkdir -p "$INSTALL_DIR"
[ -d "$EXISTING" ] && rm -rf "$EXISTING"
cp -R "$APP_PATH" "$EXISTING"
info "설치 완료"

# ── 4. 실행 ──────────────────────────────────────────
info "4/4: 앱 실행 중..."
open "$EXISTING"

info "완료!"
