# プロジェクトの成果物をここに配置してください

OpenCodeがコードを生成・保存するディレクトリです。
`docker compose up` 後、OpenCodeに指示したファイルはこのディレクトリに作られます。

## 例

- `./my-app/` — OpenCodeに「my-appを作って」と指示した場合
- `./api-server/` — 「FastAPIサーバーを作って」と指示した場合

## 注意

このディレクトリの内容は Docker volume ではなく、ホストに直接マウントされます。
`git` でバージョン管理したい場合は `projects/` 以下でリポジトリを初期化してください。
