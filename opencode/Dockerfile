# OpenCode カスタムサーバーイメージ
# ベース: 公式OpenCodeイメージ (Alpine Linux) + 開発ツール追加
FROM ghcr.io/anomalyco/opencode:latest

# 追加開発ツールのインストール (Alpine は apk を使用)
RUN apk add --no-cache \
    git \
    curl \
    wget \
    jq \
    ripgrep \
    fd \
    build-base \
    python3 \
    py3-pip \
    go \
    bash

# Node.js / npm は公式イメージに含まれているが、pnpm を追加
RUN npm install -g pnpm@latest --ignore-scripts 2>/dev/null || true

# ワークスペースディレクトリ (root で実行)
RUN mkdir -p /workspace

WORKDIR /workspace

# ヘルスチェック用スクリプト
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/healthcheck.sh

# OpenCodeをヘッドレスサーバーモードで起動
# 環境変数 OPENCODE_SERVER_PORT を参照、未設定時は 4096
EXPOSE 4096

ENTRYPOINT ["opencode", "serve", "--hostname", "0.0.0.0"]
CMD ["--port", "4096"]
