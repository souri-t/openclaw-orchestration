#!/usr/bin/env bash
# =============================================================================
# test.sh — E2E 疎通テスト
# 使い方: bash scripts/test.sh
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source .env 2>/dev/null || true

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0; FAIL=0

check() {
  local desc="$1"; local cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    echo -e "${GREEN}[PASS]${NC} $desc"
    ((PASS++)) || true
  else
    echo -e "${RED}[FAIL]${NC} $desc"
    ((FAIL++)) || true
  fi
}

echo ""
echo "====================================================================="
echo "  OpenClaw + OpenCode Orchestration — E2E テスト"
echo "====================================================================="
echo ""

OPENCODE_URL="http://localhost:${OPENCODE_SERVER_PORT:-4096}"
OPENCLAW_URL="http://localhost:${OPENCLAW_GATEWAY_PORT:-18789}"
AUTH="-u ${OPENCODE_SERVER_USERNAME:-opencode}:${OPENCODE_SERVER_PASSWORD:-}"

# --- Docker サービス確認 ---
echo "[ Docker サービス ]"
check "openclaw-gateway が running" "docker compose ps openclaw-gateway | grep -q 'running\|Up'"
check "opencode-server が running"  "docker compose ps opencode-server  | grep -q 'running\|Up'"
echo ""

# --- OpenCode API 確認 ---
echo "[ OpenCode Server API ]"
check "GET /doc が 200 応答"       "curl -sf $AUTH $OPENCODE_URL/doc"
check "GET /session が 200 応答"   "curl -sf $AUTH $OPENCODE_URL/session"
echo ""

# --- OpenCode セッション作成・メッセージ送信 ---
echo "[ OpenCode E2E フロー ]"

SESSION_ID=$(curl -sf -X POST $AUTH \
  -H "Content-Type: application/json" \
  -d '{"title": "test-session"}' \
  "$OPENCODE_URL/session" 2>/dev/null | jq -r '.id // empty')

if [ -n "$SESSION_ID" ]; then
  echo -e "${GREEN}[PASS]${NC} セッション作成 (ID: ${SESSION_ID:0:8}...)"
  ((PASS++)) || true

  # 簡単なタスクを送信
  RESULT=$(curl -sf -X POST $AUTH \
    -H "Content-Type: application/json" \
    -d '{"parts": [{"type": "text", "text": "echo Hello from OpenCode test > /workspace/projects/test-output.txt と実行して、完了したら「完了しました」と答えてください。"}]}' \
    --max-time 60 \
    "$OPENCODE_URL/session/$SESSION_ID/message" 2>/dev/null || echo "")

  if [ -n "$RESULT" ]; then
    echo -e "${GREEN}[PASS]${NC} メッセージ送信・応答取得"
    ((PASS++)) || true
    # ファイル生成確認
    sleep 2
    check "test-output.txt が生成された" "[ -f ./projects/test-output.txt ]"
  else
    echo -e "${RED}[FAIL]${NC} メッセージ送信・応答取得 (タイムアウトまたはエラー)"
    ((FAIL++)) || true
  fi
else
  echo -e "${RED}[FAIL]${NC} セッション作成"
  ((FAIL++)) || true
fi

echo ""
echo "====================================================================="
printf "  結果: ${GREEN}%d PASS${NC} / ${RED}%d FAIL${NC}\n" $PASS $FAIL
echo "====================================================================="
echo ""

[ $FAIL -eq 0 ] && exit 0 || exit 1
