#!/bin/sh
# OpenCode サーバーのヘルスチェック
# /doc エンドポイントが応答すれば正常
PORT="${OPENCODE_SERVER_PORT:-4096}"
curl -sf "http://localhost:${PORT}/doc" > /dev/null 2>&1
