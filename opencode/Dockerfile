# OpenCode カスタムサーバーイメージ
# ベース: 公式OpenCodeイメージ + 開発ツール追加
FROM ghcr.io/anomalyco/opencode:latest

# 追加開発ツールのインストール (root で実行)
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    jq \
    ripgrep \
    fd-find \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    golang-go \
    && rm -rf /var/lib/apt/lists/*

# Node.js / npm は公式イメージに含まれているが、pnpm / bun を追加
RUN npm install -g pnpm@latest bun@latest --ignore-scripts 2>/dev/null || true

# ワークスペースディレクトリ
RUN mkdir -p /workspace && chown -R node:node /workspace 2>/dev/null || \
    mkdir -p /workspace

WORKDIR /workspace

# ヘルスチェック用スクリプト
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/healthcheck.sh

# OpenCodeをヘッドレスサーバーモードで起動
# 環境変数 OPENCODE_SERVER_PORT を参照、未設定時は 4096
EXPOSE 4096

ENTRYPOINT ["opencode", "serve", "--hostname", "0.0.0.0"]
CMD ["--port", "4096"]
