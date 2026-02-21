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

# 2. .env ファイルの確認
if [ ! -f ".env" ]; then
  warn ".env ファイルが見つかりません。.env.example からコピーします..."
  cp .env.example .env
  warn ".env ファイルを編集して必要なAPIキーを設定してください:"
  warn "  - ANTHROPIC_API_KEY または他のLLMプロバイダーキー"
  warn "  - OPENCLAW_GATEWAY_TOKEN (セキュリティトークン)"
  warn "  - OPENCODE_SERVER_PASSWORD (サーバーパスワード)"
  echo ""
fi

# 3. 必須変数のチェック
source .env

MISSING_VARS=()
[ -z "${OPENROUTER_API_KEY:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${OPENAI_API_KEY:-}" ] && [ -z "${GEMINI_API_KEY:-}" ] && \
  MISSING_VARS+=("LLMプロバイダーキー (OPENROUTER_API_KEY を推奨。他に ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY のいずれか)")
[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ] && MISSING_VARS+=("OPENCLAW_GATEWAY_TOKEN")
[ -z "${OPENCODE_SERVER_PASSWORD:-}" ] && MISSING_VARS+=("OPENCODE_SERVER_PASSWORD")

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
  warn "以下の環境変数が .env に設定されていません:"
  for v in "${MISSING_VARS[@]}"; do
    warn "  - $v"
  done
  echo ""
  warn "セットアップを続行しますが、サービスが正常に起動しない可能性があります。"
  warn ".env ファイルを編集後、 docker compose up -d で再起動してください。"
  echo ""
fi

# 4. セキュリティトークン自動生成 (未設定の場合)
if [ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
  if command -v openssl >/dev/null 2>&1; then
    TOKEN=$(openssl rand -hex 32)
    sed -i.bak "s/^OPENCLAW_GATEWAY_TOKEN=.*/OPENCLAW_GATEWAY_TOKEN=${TOKEN}/" .env && rm -f .env.bak
    info "OPENCLAW_GATEWAY_TOKEN を自動生成しました。"
  fi
fi

if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ]; then
  if command -v openssl >/dev/null 2>&1; then
    PASS=$(openssl rand -hex 16)
    sed -i.bak "s/^OPENCODE_SERVER_PASSWORD=.*/OPENCODE_SERVER_PASSWORD=${PASS}/" .env && rm -f .env.bak
    info "OPENCODE_SERVER_PASSWORD を自動生成しました。"
  fi
fi

# 5. projects ディレクトリ
mkdir -p projects
touch projects/.gitkeep
info "projects/ ディレクトリを確認しました。"

# 6. Docker イメージのビルド
info "OpenCode カスタムイメージをビルドしています (初回は時間がかかります)..."
docker compose build opencode-server

info "ビルド完了！"

echo ""
echo "====================================================================="
echo "  セットアップ完了！"
echo "====================================================================="
echo ""
echo "  起動コマンド:"
echo "    docker compose up -d"
echo ""
echo "  WebChat UI:"
echo "    http://localhost:${OPENCLAW_GATEWAY_PORT:-18789}"
echo ""
echo "  OpenCode API:"
echo "    http://localhost:${OPENCODE_SERVER_PORT:-4096}/doc"
echo ""
echo "  ログ確認:"
echo "    docker compose logs -f"
echo ""
