#!/usr/bin/env bash
# =============================================================================
# setup.sh — 初回セットアップスクリプト
# 使い方: bash scripts/setup.sh
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo ""
echo "====================================================================="
echo "  OpenClaw + OpenCode Orchestration — セットアップ"
echo "====================================================================="
echo ""

# 1. 前提条件チェック
info "前提条件を確認しています..."

command -v docker >/dev/null 2>&1 || error "Docker が見つかりません。Docker Desktop をインストールしてください。"
command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 || \
  error "Docker Compose (v2) が見つかりません。Docker Desktop を最新版にアップデートしてください。"

DOCKER_RUNNING=$(docker info >/dev/null 2>&1 && echo "yes" || echo "no")
[ "$DOCKER_RUNNING" = "yes" ] || error "Docker Desktop が起動していません。起動してから再実行してください。"

info "Docker: OK ($(docker --version | cut -d' ' -f3 | tr -d ','))"
info "Docker Compose: OK ($(docker compose version --short))"

# 2. openclaw.json の準備とトークン生成
_token_current() {
  grep -o '"token": "[^"]*"' openclaw/openclaw.json 2>/dev/null | head -1 | sed 's/"token": "//;s/"//'
}

# テンプレートから openclaw.json を生成 (未存在の場合)
if [ ! -f "openclaw/openclaw.json" ]; then
  cp openclaw/openclaw.json.template openclaw/openclaw.json
  info "openclaw/openclaw.json をテンプレートから生成しました。"
fi

if [[ "$(_token_current)" == "__OPENCLAW_TOKEN_PLACEHOLDER__" ]] || [ -z "$(_token_current)" ]; then
  _OC_TOKEN=$(openssl rand -hex 32)
  sed -i.bak 's|"token": "[^"]*"|"token": "'"${_OC_TOKEN}"'"|' openclaw/openclaw.json && rm -f openclaw/openclaw.json.bak
  info "OpenClaw トークンを openclaw.json に設定しました。"
fi

# allowedOrigins にホスト名を追加 (ローカルネットワークからのアクセスに対応)
_HOST=$(hostname -s 2>/dev/null || hostname)
python3 - << PYEOF
import json, subprocess
path = "openclaw/openclaw.json"
with open(path) as f:
    data = json.load(f)

host = "${_HOST}"
origins = {
    "http://localhost:18789",
    f"http://{host}:18789",
    f"http://{host}.local:18789",
}
data.setdefault("gateway", {}).setdefault("controlUi", {})["allowedOrigins"] = sorted(origins)

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("allowedOrigins updated:", sorted(origins))
PYEOF
info "allowedOrigins を更新しました ($HOST / $HOST.local)。"

# 3. .env の自動生成 (OpenCode 専用)
_gen_env() {
  local api_key="$1" pass
  pass=$(openssl rand -hex 16)
  cat > .env << ENV_EOF
# このファイルは setup.sh によって自動生成されました (OpenCode 専用)
OPENROUTER_API_KEY=$api_key
OPENCODE_MODEL=openrouter/anthropic/claude-sonnet-4-5
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=ap-northeast-1
OPENCODE_SERVER_PASSWORD=$pass
OPENCODE_SERVER_USERNAME=opencode
ENV_EOF
}

if [ ! -f ".env" ]; then
  echo ""
  echo "  OpenCode が使用する LLM の API キーを設定します。"
  echo "  取得: https://openrouter.ai/keys"
  echo -n "  OPENROUTER_API_KEY > "
  read -r _api_key
  _gen_env "$_api_key"
  info ".env を生成しました。"
else
  source .env
  if [ -z "${OPENROUTER_API_KEY:-}" ] || [[ "${OPENROUTER_API_KEY}" == sk-or-v1-xxx* ]]; then
    warn "OPENROUTER_API_KEY が未設定です。"
    echo -n "  OPENROUTER_API_KEY > "
    read -r _api_key
    sed -i.bak "s|^OPENROUTER_API_KEY=.*|OPENROUTER_API_KEY=${_api_key}|" .env && rm -f .env.bak
    info "OPENROUTER_API_KEY を更新しました。"
  fi
  source .env
  if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ] || [[ "${OPENCODE_SERVER_PASSWORD}" == change-me* ]]; then
    PASS=$(openssl rand -hex 16)
    grep -q "^OPENCODE_SERVER_PASSWORD=" .env \
      && sed -i.bak "s|^OPENCODE_SERVER_PASSWORD=.*|OPENCODE_SERVER_PASSWORD=${PASS}|" .env && rm -f .env.bak \
      || echo "OPENCODE_SERVER_PASSWORD=${PASS}" >> .env
    info "OPENCODE_SERVER_PASSWORD を自動生成しました。"
  fi
fi

# 5. 必要なディレクトリ作成
mkdir -p projects openclaw/agents opencode-data
info "projects/ / openclaw/agents/ ディレクトリを確認しました。"

# 6. Docker イメージのビルド
info "OpenCode カスタムイメージをビルドしています (初回は時間がかかります)..."
docker compose build opencode-server

info "ビルド完了！"

# 7. コンテナ起動
info "コンテナを起動しています..."
docker compose up -d

# 8. openclaw-gateway ヘルスチェック待機
info "openclaw-gateway の起動を待っています..."
for i in $(seq 1 30); do
  STATUS=$(docker compose ps openclaw-gateway --format json 2>/dev/null \
    | python3 -c "import sys,json; rows=[l for l in sys.stdin.read().splitlines() if l.strip()]; print(json.loads(rows[0]).get('Health','') if rows else '')" 2>/dev/null || echo "")
  if [ "$STATUS" = "healthy" ]; then
    info "openclaw-gateway: healthy"
    break
  fi
  if [ "$i" -eq 30 ]; then
    warn "ヘルスチェックタイムアウト。コンテナログを確認してください:"
    warn "  docker compose logs openclaw-gateway"
  fi
  printf "  waiting... (%d/30)\r" "$i"
  sleep 5
done
echo ""

# 9. OpenClaw エージェント モデル設定 (インタラクティブ)
echo ""
echo "====================================================================="
echo "  OpenClaw エージェントのモデル / API キーを設定します"
echo "  ウィザードに従って入力してください"
echo "====================================================================="
echo ""
docker compose exec openclaw-gateway node /app/openclaw.mjs configure --section model

# 10. 完了メッセージ
_OC_TOKEN=$(_token_current)
echo ""
echo "====================================================================="
echo "  セットアップ完了！"
echo "====================================================================="
echo ""
echo "  WebChat UI:"
echo "    http://localhost:18789/?token=${_OC_TOKEN}&gatewayUrl=ws://localhost:18789"
echo ""
echo "  OpenCode API ドキュメント:"
echo "    http://localhost:4096/doc"
echo ""
echo "  コンテナ再起動:"
echo "    docker compose restart openclaw-gateway"
echo ""
echo "  ログ確認:"
echo "    docker compose logs -f"
echo ""
