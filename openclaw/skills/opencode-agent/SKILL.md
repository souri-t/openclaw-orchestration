---
name: opencode-agent
description: |
  OpenCodeコーディングエージェントにコーディングタスクを委譲します。
  Dockerコンテナ上で動作するOpenCodeサーバーにHTTP APIで接続し、
  コードの作成・編集・デバッグ・リファクタリングなどの開発作業を実行させます。
  成果物は /workspace/projects ディレクトリに保存されます。
metadata: {
  "openclaw": {
    "requires": {
      "bins": ["curl", "jq"],
      "env": ["OPENCODE_SERVER_URL", "OPENCODE_SERVER_PASSWORD"]
    },
    "primaryEnv": "OPENCODE_SERVER_URL"
  }
}
---

# OpenCode Agent スキル

あなたはOpenClawオーケストレーターとして、ユーザーから開発タスクを受け取り、OpenCodeコーディングエージェントに委譲する役割を担います。

## OpenCode サーバー情報

- **BaseURL**: `$OPENCODE_SERVER_URL` (デフォルト: `http://opencode-server:4096`)
- **認証**: Basic認証 — ユーザー名 `$OPENCODE_SERVER_USERNAME` / パスワード `$OPENCODE_SERVER_PASSWORD`
- **API仕様**: `$OPENCODE_SERVER_URL/doc` で確認可能

## タスク実行フロー

ユーザーからコーディングタスクの依頼を受けたら、以下の手順で作業を実行してください。

### Step 1: OpenCode サーバーの疎通確認

```bash
curl -sf \
  -u "$OPENCODE_SERVER_USERNAME:$OPENCODE_SERVER_PASSWORD" \
  "$OPENCODE_SERVER_URL/doc" | jq '.info.title'
```

疎通できない場合は、サーバーが起動中か確認するようユーザーに伝えてください。

### Step 2: セッションの作成

```bash
SESSION_RESPONSE=$(curl -sf -X POST \
  -u "$OPENCODE_SERVER_USERNAME:$OPENCODE_SERVER_PASSWORD" \
  -H "Content-Type: application/json" \
  -d "{\"title\": \"$(date '+%Y%m%d-%H%M%S') - タスク\"}" \
  "$OPENCODE_SERVER_URL/session")

SESSION_ID=$(echo "$SESSION_RESPONSE" | jq -r '.id')
echo "セッションID: $SESSION_ID"
```

### Step 3: タスクを OpenCode に送信 (同期実行・応答待ち)

```bash
TASK_PROMPT="<ユーザーから受け取ったタスク内容をここに挿入>"

RESULT=$(curl -sf -X POST \
  -u "$OPENCODE_SERVER_USERNAME:$OPENCODE_SERVER_PASSWORD" \
  -H "Content-Type: application/json" \
  -d "{
    \"parts\": [
      {
        \"type\": \"text\",
        \"text\": \"$TASK_PROMPT\"
      }
    ]
  }" \
  --max-time 300 \
  "$OPENCODE_SERVER_URL/session/$SESSION_ID/message")

echo "$RESULT" | jq -r '.[-1].parts[] | select(.type == "text") | .text'
```

**注意**: `--max-time 300` は最大5分待機。長いタスクは非同期モード (prompt_async) を使用。

### Step 4: 結果の確認

```bash
# セッションのメッセージ履歴を取得
curl -sf \
  -u "$OPENCODE_SERVER_USERNAME:$OPENCODE_SERVER_PASSWORD" \
  "$OPENCODE_SERVER_URL/session/$SESSION_ID/message" | \
  jq -r '.[-1].parts[] | select(.type == "text") | .text'
```

### Step 5: 作業結果のファイル確認

OpenCodeが生成したファイルは `/workspace/projects/` 以下に保存されています。
ホスト側の `./projects/` ディレクトリから直接確認できます。

## 非同期タスク実行 (長時間タスク向け)

5分以上かかるタスクは非同期モードを使用してください:

```bash
# 非同期でプロンプト送信
curl -sf -X POST \
  -u "$OPENCODE_SERVER_USERNAME:$OPENCODE_SERVER_PASSWORD" \
  -H "Content-Type: application/json" \
  -d "{\"parts\": [{\"type\": \"text\", \"text\": \"$TASK_PROMPT\"}]}" \
  "$OPENCODE_SERVER_URL/session/$SESSION_ID/prompt_async"

# SSEイベントで進捗を監視 (別コマンド)
# curl -N "$OPENCODE_SERVER_URL/event" -u "$OPENCODE_SERVER_USERNAME:$OPENCODE_SERVER_PASSWORD"
```

## 複数プロジェクト対応

複数のプロジェクトを並行して扱う場合、プロジェクトごとに異なるセッションを作成してください:

```bash
# プロジェクトA用セッション
SESSION_A=$(curl -sf -X POST \
  -u "$OPENCODE_SERVER_USERNAME:$OPENCODE_SERVER_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"title": "ProjectA"}' \
  "$OPENCODE_SERVER_URL/session" | jq -r '.id')

# 作業ディレクトリを指定したプロンプト (タスク内に明示する)
PROMPT="プロジェクトは /workspace/projects/project-a/ に作成してください。..."
```

## タスク中断

実行中のタスクを中断する場合:

```bash
curl -sf -X POST \
  -u "$OPENCODE_SERVER_USERNAME:$OPENCODE_SERVER_PASSWORD" \
  "$OPENCODE_SERVER_URL/session/$SESSION_ID/abort"
```

## ユーザーへの報告

作業完了後、以下の情報をユーザーに報告してください:
1. 実行したタスクの概要
2. 作成/変更されたファイルの一覧
3. 次に取り組むべきことの提案 (あれば)
4. エラーが発生した場合はその内容と対処法
