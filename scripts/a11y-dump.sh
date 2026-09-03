#!/bin/bash
# a11y-dump.sh — macOS 접근성 덤프 (텍스트 전용 모델 대응)
# usage: ./scripts/a11y-dump.sh [output_dir]

set -euo pipefail

OUTPUT_DIR="${1:-docs/screenshots/macos}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUTPUT_DIR"

echo "[INFO] 접근성 덤프 캡처 중..."

# 활성 앱의 접근성 트리 덤프
AX_APP=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || echo "Unknown")
echo "[INFO] 대상 앱: ${AX_APP}"

#榅 UI 구조 덤프 (AXTree)
osascript -e "
tell application \"System Events\"
    set frontApp to first application process whose frontmost is true
    set frontWindow to front window of frontApp
    set output to \"\"
    try
        set output to entire contents of frontWindow
    on error
        set output to \"AX tree dump failed\"
    end try
    return output
end tell
" > "${OUTPUT_DIR}/a11y_tree_${TIMESTAMP}.txt" 2>/dev/null || echo "AX tree dump 실패" > "${OUTPUT_DIR}/a11y_tree_${TIMESTAMP}.txt"

echo "[INFO] 저장: ${OUTPUT_DIR}/a11y_tree_${TIMESTAMP}.txt"

# 디버그 로그 덤프 (DebugLogger가 초기화된 경우)
# 앱이 실행 중이면 로그를 파일로 내보내기
echo "[INFO] a11y-dump 완료!"
