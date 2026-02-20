# OpenClaw + OpenCode Orchestration

OpenClawのWebChat UIからAI開発エージェント（OpenCode）にコーディングタスクを委譲するDockerオーケストレーションシステム。

## システム構成

```
ユーザー (ブラウザ)
       │
       ▼  http://localhost:18789
┌──────────────────────────────────────┐
│  openclaw-gateway                    │
│  ・WebChat UI                        │
│  ・チャネル統合 (Slack/Telegram等)     │
│  ・スキル: opencode-agent             │
└──────────────┬───────────────────────┘
               │  HTTP API (docker内部: http://opencode-server:4096)
               ▼
┌──────────────────────────────────────┐
│  opencode-server                     │
│  ・opencode serve --port 4096        │
│  ・LLM連携 (Anthropic/OpenAI等)       │
│  ┌──────────────────────────────┐    │
│  │ /workspace/projects/ (volume)│    │  ←→ ./projects/ (ホスト)
│  └──────────────────────────────┘    │
└──────────────────────────────────────┘
```

| サービス | ポート | 役割 |
|---------|--------|------|
| `openclaw-gateway` | 18789, 18790 | コントロールプレーン + WebChat UI |
| `opencode-server` | 4096 | ヘッドレスコーディングエージェント |

## 前提条件

- **Docker Desktop for Mac** (v4.x 以上)
- **LLMプロバイダーのAPIキー** (Anthropic / OpenAI / Google のいずれか1つ)
- macOS Monterey 以上

## クイックスタート

### 1. セットアップ

```bash
# リポジトリのクローン (または既にある場合はスキップ)
cd /path/to/openclaw-orchestration

# セットアップスクリプトを実行
bash scripts/setup.sh
```

セットアップスクリプトが以下を自動実行します:
- 前提条件チェック
- `.env` ファイルの生成 (未存在の場合)
- セキュリティトークン・パスワードの自動生成
- OpenCode Dockerイメージのビルド

### 2. .env を編集

```bash
# .env を開いてAPIキーを設定
nano .env   # または好みのエディタで
```

**最低限必要な設定:**
```env
ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxx    # Anthropic APIキー
OPENCLAW_GATEWAY_TOKEN=<自動生成済み>
OPENCODE_SERVER_PASSWORD=<自動生成済み>
```

### 3. 起動

```bash
docker compose up -d
```

初回起動は OpenCode イメージをビルドするため数分かかります。

### 4. WebChat にアクセス

ブラウザで [http://localhost:18789](http://localhost:18789) を開きます。

**OpenClawの初回セットアップ:**
1. WebChat UIにアクセス
2. 認証トークン (`.env` の `OPENCLAW_GATEWAY_TOKEN`) を入力
3. チャット画面で以下のように OpenCode-Agent スキルを使って指示します:

```
Hello! Python製のFlaskサーバーを /workspace/projects/flask-app に作ってください。
エンドポイントは / (Hello World) と /health の2つだけでOKです。
```

## 使い方

### 基本的な指示例

```
# 新しいアプリの作成
Reactのカウンターアプリを projects/counter-app に作ってください。

# 既存コードの修正
projects/my-api の app.py にエラーハンドリングを追加してください。

# コードレビュー
projects/my-service にあるコードをレビューして改善点を教えてください。

# テスト作成
projects/utils/helpers.py のユニットテストを pytest で書いてください。
```

### 成果物の確認

OpenCodeが生成したファイルはホスト側の `./projects/` ディレクトリに直接保存されます:

```bash
ls -la ./projects/
```

### OpenCode API に直接アクセス

```bash
# API仕様の確認
curl -u opencode:$OPENCODE_SERVER_PASSWORD http://localhost:4096/doc | jq .

# セッション一覧
curl -u opencode:$OPENCODE_SERVER_PASSWORD http://localhost:4096/session | jq .

# 新しいセッションを作成してタスク送信
SESSION=$(curl -s -X POST -u opencode:$OPENCODE_SERVER_PASSWORD \
  -H "Content-Type: application/json" \
  -d '{"title": "my-task"}' \
  http://localhost:4096/session | jq -r '.id')

curl -s -X POST -u opencode:$OPENCODE_SERVER_PASSWORD \
  -H "Content-Type: application/json" \
  -d '{"parts": [{"type": "text", "text": "Hello! 簡単なPythonスクリプトを作ってください。"}]}' \
  --max-time 120 \
  "http://localhost:4096/session/$SESSION/message" | jq -r '.[-1].parts[].text'
```

## E2E テスト

```bash
bash scripts/test.sh
```

## ログ確認

```bash
# 全サービスのログ
docker compose logs -f

# 特定サービスのみ
docker compose logs -f openclaw-gateway
docker compose logs -f opencode-server
```

## 停止・再起動

```bash
# 停止 (データは保持)
docker compose down

# データごと削除 (リセット)
docker compose down -v

# OpenCodeイメージの再ビルド
docker compose build --no-cache opencode-server
docker compose up -d
```

## ディレクトリ構成

```
openclaw-orchestration/
├── docker-compose.yml              # サービス定義
├── .env                            # 環境変数 (gitignore対象)
├── .env.example                    # 環境変数テンプレート
├── openclaw/
│   ├── openclaw.json               # OpenClaw Gateway 設定 (JSON5)
│   └── skills/
│       └── opencode-agent/
│           └── SKILL.md            # OpenCode連携スキル定義
├── opencode/
│   ├── Dockerfile                  # OpenCodeカスタムイメージ
│   ├── healthcheck.sh              # ヘルスチェックスクリプト
│   └── opencode.json               # OpenCode設定
├── projects/                       # 開発成果物の格納先 (ホストとコンテナで共有)
└── scripts/
    ├── setup.sh                    # 初回セットアップ
    └── test.sh                     # E2Eテスト
```

## チャネル連携の追加 (オプション)

Slack、Telegram 等のチャネルと連携する場合は `.env` と `openclaw/openclaw.json` の該当箇所のコメントを外して設定します。

## トラブルシューティング

### `opencode-server` が起動しない

```bash
# ログ確認
docker compose logs opencode-server

# イメージ再ビルド
docker compose build --no-cache opencode-server
```

→ `ANTHROPIC_API_KEY` 等が設定されているか `.env` を確認してください。

### `openclaw-gateway` に WebChat でアクセスできない

```bash
# サービス状態確認
docker compose ps

# ネットワーク確認
docker network ls | grep openclaw
```

→ `OPENCLAW_GATEWAY_TOKEN` が `.env` に設定されているか確認してください。

### OpenCode が応答に時間がかかる

LLMへのAPIコールは数秒〜数十秒かかります。長いタスクは `scripts/test.sh` の非同期 API (`prompt_async`) を参考に実装してください。

---

## 参考リンク

- [OpenClaw 公式ドキュメント](https://openclaw.ai/docs)
- [OpenCode (anomalyco/opencode)](https://github.com/anomalyco/opencode)
- [OpenCode API Reference](http://localhost:4096/doc) (起動後にアクセス可能)
- [ClawHub — スキルレジストリ](https://clawhub.ai/)
