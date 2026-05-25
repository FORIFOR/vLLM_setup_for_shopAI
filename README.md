# ShopAI vLLM LLM Node

店舗案内 AI「ShopAI」用の **LLM サーバ(推論ノード)** のセットアップ一式。
GPU PC 上で vLLM を Docker で常駐させ、OpenAI 互換 API を公開します。
店舗業務ロジック(RAG / Policy / TTS 等)は別リポジトリのバックエンドが担当し、ここは**推論だけ**を提供します。

```
Android ──> ShopAI Backend (192.168.0.6) ──> このノード (192.168.0.15:8000)
                                                └─ vLLM / Qwen3-8B-AWQ
                                                   公開名: shopai-fast
```

| 項目 | 値 |
|---|---|
| 実行ホスト | GPU PC（例: 192.168.0.15 / RTX 5070 Ti） |
| 公開ポート | `8000`（OpenAI 互換） |
| 公開モデル名 | **`shopai-fast`**（`--served-model-name`） |
| 実モデル | `Qwen/Qwen3-8B-AWQ`（`.env` の `VLLM_MODEL` で変更可） |
| 認証 | `Authorization: Bearer <VLLM_API_KEY>` |
| 自動起動 | `docker compose`(`restart: unless-stopped`) + docker.service(enabled) |

---

## 前提

- NVIDIA GPU + ドライバ導入済み（`nvidia-smi` が表示される）
- Docker / `docker compose`
- NVIDIA Container Toolkit（未導入なら下の手順1で導入）

> このノードの `saiteku` ユーザは docker グループ未所属の想定です。`docker` 系コマンドは **`sudo`** を付けて実行してください（`start_vllm.sh` 等のスクリプトは内部で `docker` を呼ぶため `sudo bash <script>` で実行）。

---

## セットアップ手順

```bash
# 0) 取得して移動
git clone https://github.com/FORIFOR/vLLM_setup_for_shopAI.git ~/shopai-llm-server
cd ~/shopai-llm-server

# 1) NVIDIA Container Toolkit（未導入の場合のみ）
sudo bash install_nvidia_toolkit.sh

# 2) APIキーを設定
cp .env.example .env
openssl rand -hex 32        # 出力をコピー
nano .env                   # VLLM_API_KEY=<上の値> に書き換え（VLLM_MODEL は既定でOK）

# 3) 起動（イメージ取得 + モデルDL/ロード + readiness 監視）
sudo bash start_vllm.sh
#   初回は Qwen3-8B-AWQ(約5.7GB)のDLで数分かかります。

# 4) 状態確認（sudo不要）
bash status.sh
```

`status.sh` が `✅ READY (... model=shopai-fast)` を表示すれば起動完了です。

---

## ファイアウォール（推奨・本番）

8000 番をバックエンド(192.168.0.6)からのみ到達可能にし、SSH 以外の incoming を遮断します。
Docker の公開ポートは ufw を迂回するため `DOCKER-USER` でも制限し、再起動後も systemd で再適用されます。

```bash
sudo bash harden_node.sh
```

> `BACKEND_IP` / `VLLM_PORT` を変える場合は `harden_node.sh` 冒頭を編集してください。
> 127.0.0.1 と自ホストからのローカルテストは引き続き可能です。

---

## 動作確認 / 運用スクリプト

| スクリプト | sudo | 内容 |
|---|---|---|
| `status.sh` | 不要 | API が READY か即確認（`/v1/models` を叩く） |
| `test_parallel_llm.py` | 不要 | 8 並列で `/v1/chat/completions` を叩く負荷テスト |
| `verify_autostart.sh` | 必要 | 自動起動の健全性（restart policy / ドライバ整合 / API）一括検証 |
| `check_backend_traffic.sh` | 必要 | Backend(192.168.0.6) からの実リクエストがログにあるか確認 |

```bash
bash status.sh
python3 test_parallel_llm.py
sudo bash verify_autostart.sh
sudo bash check_backend_traffic.sh
```

手動の疎通テスト:

```bash
KEY=$(grep VLLM_API_KEY .env | cut -d= -f2- | tr -d '"')
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"shopai-fast","messages":[{"role":"system","content":"店舗スタッフです。2文以内。/no_think"},{"role":"user","content":"営業時間は?"}],"max_tokens":96}'
```

---

## クライアント（バックエンド）側の契約 ※重要

このノードを呼ぶ側は次を守ること:

1. **`model` は `shopai-fast`** を送る。`shopai-fast-active` 等の別名は **HTTP 404**。
2. **`Authorization: Bearer <VLLM_API_KEY>`** を付ける（無い/誤りは 401）。
3. **思考トークン対策**: Qwen3 は既定で思考を出す。system に `/no_think` を入れ、**かつ** 応答から `<think>...</think>` を除去する（`/no_think` のみだと空の `<think></think>` が残るため両方必要）。

---

## モデルの切り替え

`.env` の `VLLM_MODEL` を変更して再起動するだけ。公開名 `shopai-fast` は固定なので**バックエンドの設定変更は不要**です。

```bash
nano .env                 # 例: VLLM_MODEL="Qwen/Qwen3-14B-AWQ"
sudo bash start_vllm.sh   # 再ロード（切替中は数十秒〜数分の停止あり）
```

VRAM に応じて `docker-compose.yml` の `--max-model-len` / `--max-num-seqs` / `--gpu-memory-utilization` を調整してください。

---

## 自動起動について

- コンテナは `restart: unless-stopped`、`docker.service` は `enabled`。**ホスト再起動後に自動でコンテナが起動し、モデルをロードして READY** になります（実機確認済み）。
- NVIDIA ドライバを `apt` 更新した直後は、ホストを **再起動するまで** カーネルモジュールとユーザ空間ライブラリのバージョンが食い違い、`nvidia-smi` が `Driver/library version mismatch` を出すことがあります。この状態でコンテナが再起動すると GPU 初期化に失敗するため、**ドライバ更新後は計画的に再起動**してください（`verify_autostart.sh` の項目4・5で検知できます）。

---

## トラブルシュート

| 症状 | 対処 |
|---|---|
| `status.sh` が NOT READY | 起動直後はモデルロードに1〜2分。`sudo docker compose logs --tail=50 shopai-fast-llm` でログ確認。 |
| chat が 404 | クライアントの `model` を `shopai-fast` にする。 |
| chat が 401 | `Authorization: Bearer <VLLM_API_KEY>` を確認。 |
| 応答に `<think>` 混入 | クライアント側で `/no_think` 注入 + `<think>...</think>` 除去。 |
| `nvidia-smi` が mismatch | ドライバ更新後の未再起動。`sudo reboot`。 |
| Backend から繋がらない | `harden_node.sh` の `BACKEND_IP` を確認。Backend VM から `curl http://192.168.0.15:8000/v1/models -H "Authorization: Bearer <KEY>"` が 200 か。 |
| `docker: permission denied` | `sudo` を付ける、または user を docker グループに追加。 |
