# Nyaitter CLI

ターミナルから Nyaitter を操作できるコマンドラインツールです。
通常のコマンド操作に加えて、ターミナル上で動く TUI（画面表示）クライアントも利用できます。

---

## インストール

```bash
cd Nyaitter-CLI
./install.sh
```

---

## 初期設定

```bash
# サーバーURLの設定 (例: https://nyaitter.example.com)
nyaitter config set url <NyaitterサーバーURL>

# APIキーの設定
nyaitter config set token <発行したAPIキー>

# ログイン確認
nyaitter whoami
```

---

## 画面表示モード (TUI)

ターミナル上でフルスクリーンのクライアントを起動します：

```bash
nyaitter tui
```

### 画面の切り替え (`1`〜`6`)
- `1`: **ホーム** (タイムライン / Tabキーでおすすめ・フォロー中切り替え)
- `2`: **トレンド / 検索** (話題の投稿 / `/`キーで検索)
- `3`: **通知** (`A`キーで全既読)
- `4`: **DM** (`s`キーで送信)
- `5`: **マイページ** (自分の投稿・フォロワー情報)
- `6`: **設定** (`k`キーでAPIキーログイン)

### 主なキー操作
- `j` / `k` (または `↓` / `↑`): 移動
- `Enter`: 投稿の詳細表示
- `p`: 新規投稿
- `c`: 返信
- `l`: いいね
- `t`: リポスト
- `r`: 画面更新
- `?`: ヘルプ
- `q`: 終了

---

## 主なコマンド (CLI)

```bash
# タイムラインの表示
nyaitter tl

# 投稿
nyaitter post "こんにちは！"

# 返信
nyaitter post "返信です" --reply-to <投稿ID>

# いいね・リポスト
nyaitter like <投稿ID>
nyaitter repost <投稿ID>

# ユーザー情報
nyaitter user <ユーザー名またはID>
nyaitter follow <ユーザーID>

# 通知
nyaitter notif
nyaitter notif read

# スクリプト連携用 (JSON出力)
nyaitter tl --json
```
