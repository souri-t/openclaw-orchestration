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
- `OPENROUTER_API_KEY` の入力 (OpenRouter: https://openrouter.ai/keys)
- インフラ変数 (トークン・パスワード) の自動生成
- OpenCode Dockerイメージのビルド
- コンテナ起動 → OpenClaw モデル設定ウィザード

### 2. 起動

```bash
docker compose up -d
```

初回起動は OpenCode イメージをビルドするため数分かかります。

### 3. WebChat にアクセス

ブラウザで [http://localhost:18789](http://localhost:18789) を開きます。

**OpenClawの初回セットアップウィザード (CLI):**

コンテナ起動後、インタラクティブなセットアップウィザードを起動できます:

```bash
docker compose exec openclaw-gateway node /app/openclaw.mjs configure
```

特定セクションのみ設定する場合:

```bash
# モデル設定のみ
docker compose exec openclaw-gateway node /app/openclaw.mjs configure --section model

# チャンネル設定のみ (Slack / Telegram 等)
docker compose exec openclaw-gateway node /app/openclaw.mjs configure --section channels
```

利用可能なセクション: `workspace`, `model`, `web`, `gateway`, `daemon`, `channels`, `skills`, `health`

**WebChat のオンボーディングUIを開く:**

ブラウザで以下の URL にアクセスすると、オンボーディング画面が開きます:

```
http://localhost:18789/?token=<トークン>&gatewayUrl=ws://localhost:18789&onboarding=1
```

トークンは `setup.sh` 完了時に表示されます。また `openclaw/openclaw.json` の `gateway.auth.token` フィールドで確認できます。

**通常のWebChatアクセス:**
1. WebChat UIにアクセス
2. 認証トークン (`openclaw/openclaw.json` の `gateway.auth.token`) を入力 (setup.sh 完了時に URL として表示されます)
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
├── .env                            # 環境変数 (setup.sh 自動生成 / gitignore対象)
├── openclaw/
│   ├── openclaw.json               # OpenClaw Gateway 設定 (setup.sh 生成 / gitignore対象)
│   ├── openclaw.json.template      # 設定テンプレート (git管理)
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

→ `OPENROUTER_API_KEY` が `.env` に設定されているか確認してください。スクリプト再実行: `bash scripts/setup.sh`

### `openclaw-gateway` に WebChat でアクセスできない

```bash
# サービス状態確認
docker compose ps

# ネットワーク確認
docker network ls | grep openclaw
```

→ `.env` の内容を確認し、必要なら `bash scripts/setup.sh` を再実行してください。

### OpenCode が応答に時間がかかる

LLMへのAPIコールは数秒〜数十秒かかります。長いタスクは `scripts/test.sh` の非同期 API (`prompt_async`) を参考に実装してください。

---

## 参考リンク

- [OpenClaw 公式ドキュメント](https://openclaw.ai/docs)
- [OpenCode (anomalyco/opencode)](https://github.com/anomalyco/opencode)
- [OpenCode API Reference](http://localhost:4096/doc) (起動後にアクセス可能)
- [ClawHub — スキルレジストリ](https://clawhub.ai/)
