#!/usr/bin/env bash
# vLLM コンテナの「自動起動」状態を一括検証する（読み取りのみ・sudo必須）。
# 実行: ! sudo bash ~/shopai-llm-server/verify_autostart.sh
# 再起動の前後どちらでも使える。再起動後は全項目 OK になることを期待する。
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$DIR"
KEY="$(grep -E '^VLLM_API_KEY' .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")"

line() { printf '\n==== %s ====\n' "$1"; }

line "1. docker デーモン自動起動(boot時)"
systemctl is-enabled docker; systemctl is-active docker

line "2. コンテナ稼働状態 (docker compose ps)"
docker compose ps

line "3. コンテナ restart ポリシー / 再起動回数 (docker inspect)"
docker inspect shopai-fast-llm --format \
  'Running={{.State.Running}}  Status={{.State.Status}}  RestartPolicy={{.HostConfig.RestartPolicy.Name}}  RestartCount={{.RestartCount}}  StartedAt={{.State.StartedAt}}' \
  2>/dev/null || echo "!! コンテナが存在しません (起動していない)"

line "4. NVIDIA ドライバ整合性チェック"
KMOD="$(sed -nE 's/.*Kernel Module +([0-9.]+).*/\1/p' /proc/driver/nvidia/version 2>/dev/null)"
[ -z "$KMOD" ] && KMOD="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' /proc/driver/nvidia/version 2>/dev/null | head -1)"
ULIB="$(ls /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.* 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
echo "ロード中カーネルモジュール : ${KMOD:-不明}"
echo "ユーザ空間NVMLライブラリ   : ${ULIB:-不明}"
if [ -n "$KMOD" ] && [ "$KMOD" = "$ULIB" ]; then echo "→ ✅ 一致"; else echo "→ ⚠️ 不一致 (再起動が必要 / コンテナ再起動でGPU初期化失敗の恐れ)"; fi
echo "--- nvidia-smi ---"
nvidia-smi --query-gpu=driver_version,memory.used,memory.total,utilization.gpu --format=csv,noheader 2>&1

line "5. 再起動保留フラグ"
if [ -f /var/run/reboot-required ]; then echo "⚠️ 再起動が保留中"; else echo "✅ なし"; fi

line "6. API /v1/models (HTTP応答)"
code="$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/v1/models -H "Authorization: Bearer ${KEY}" 2>/dev/null || echo 000)"
echo "HTTP ${code}  $([ "$code" = "200" ] && echo '✅ READY' || echo '⏳ NOT READY (起動直後はモデルロードに1-2分)')"

line "7. chat/completions 疎通"
curl -s -m 60 http://127.0.0.1:8000/v1/chat/completions \
  -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" \
  -d '{"model":"shopai-fast","messages":[{"role":"user","content":"ping"}],"max_tokens":8}' \
  -o /dev/null -w 'chat HTTP %{http_code}\n' 2>&1

echo
echo "==== 判定 ===="
echo "全項目で Running=true / RestartPolicy=unless-stopped / ドライバ一致 / HTTP 200 なら自動起動は健全。"
