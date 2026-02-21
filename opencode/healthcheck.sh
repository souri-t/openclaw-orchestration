#!/bin/sh
# OpenCode サーバーのヘルスチェック
# /doc エンドポイントが応答すれば正常 (Basic認証必須)
PORT="${OPENCODE_SERVER_PORT:-4096}"
USER="${OPENCODE_SERVER_USERNAME:-opencode}"
PASS="${OPENCODE_SERVER_PASSWORD:-}"
curl -sf -u "${USER}:${PASS}" "http://localhost:${PORT}/doc" > /dev/null 2>&1
