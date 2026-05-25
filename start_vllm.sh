#!/usr/bin/env bash
# vLLM (Qwen3-8B-AWQ) を起動し、APIが応答するまで監視する。
# 実行: sudo bash ~/shopai-llm-server/start_vllm.sh
set -uo pipefail
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$DIR"

# .env から API キーを読込（最終確認用）
KEY="$(grep -E '^VLLM_API_KEY' .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")"

echo "== docker compose up -d (イメージ取得 + コンテナ起動) =="
docker compose up -d
echo
echo "== コンテナ状態 =="
docker compose ps

echo
echo "== モデルDL/ロード待機 (最大30分・10秒間隔で監視) =="
ready=0
for i in $(seq 1 180); do
  state="$(docker inspect -f '{{.State.Status}}' shopai-fast-llm 2>/dev/null || echo missing)"
  if [ "$state" != "running" ] && [ "$state" != "created" ]; then
    echo
    echo "!! コンテナ状態が '$state' になりました（異常終了の可能性）。ログ末尾:"
    docker compose logs --tail=80 shopai-fast-llm
    exit 1
  fi
  code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/v1/models 2>/dev/null || echo 000)"
  if [ "$code" = "200" ] || [ "$code" = "401" ]; then
    ready=1
    echo
    echo "READY: HTTPサーバ応答 (code=$code) 約$((i*10))秒経過"
    break
  fi
  printf '.'
  sleep 10
done
echo

if [ "$ready" -ne 1 ]; then
  echo "!! 30分以内に起動を確認できませんでした。ログ末尾:"
  docker compose logs --tail=100 shopai-fast-llm
  exit 1
fi

echo "== /v1/models (認証付き) =="
curl -s http://127.0.0.1:8000/v1/models -H "Authorization: Bearer ${KEY}"
echo
echo
echo "== 直近ログ20行 =="
docker compose logs --tail=20 shopai-fast-llm
echo
echo "✅ vLLM 起動確認OK。次は chat/completions テストへ。"
