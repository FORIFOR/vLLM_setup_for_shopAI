#!/usr/bin/env bash
# vLLM ノードの ready 状態をすばやく確認（sudo不要）。
# 実行: bash ~/shopai-llm-server/status.sh
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
KEY="$(grep -E '^VLLM_API_KEY' "$DIR/.env" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")"

code="$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/v1/models -H "Authorization: Bearer ${KEY}" 2>/dev/null || echo 000)"
if [ "$code" = "200" ]; then
  echo "✅ READY  (http://192.168.0.15:8000/v1, model=shopai-fast)"
  curl -s http://127.0.0.1:8000/v1/models -H "Authorization: Bearer ${KEY}" \
    | tr ',' '\n' | grep -E '"id"|"max_model_len"' | head -2
else
  echo "⏳ NOT READY yet (HTTP ${code}) — 起動直後はモデルロードに1〜2分かかります"
  echo "   ログ: sudo docker compose -f $DIR/docker-compose.yml logs --tail=20 shopai-fast-llm"
fi
echo "--- GPU ---"
nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader 2>/dev/null