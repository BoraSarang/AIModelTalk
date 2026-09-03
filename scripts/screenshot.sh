#!/bin/bash
# screenshot.sh — macOS 스크린샷 캡처
# usage: ./scripts/screenshot.sh [output_dir]

set -euo pipefail

OUTPUT_DIR="${1:-docs/screenshots/macos}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUTPUT_DIR"

echo "[INFO] 스크린샷 캡처 중..."

# 전체 화면 스크린샷
screencapture -x "${OUTPUT_DIR}/screen_${TIMESTAMP}.png"
echo "[INFO] 저장: ${OUTPUT_DIR}/screen_${TIMESTAMP}.png"

# 활성 윈도우만
screencapture -x -w "${OUTPUT_DIR}/window_${TIMESTAMP}.png"
echo "[INFO] 저장: ${OUTPUT_DIR}/window_${TIMESTAMP}.png"

echo "[INFO] 완료!"
