#!/usr/bin/env bash
# Backend VM(192.168.0.6)からのリクエストが実際に届いているかを検証する（sudo必須）。
# 実行: ! sudo bash ~/shopai-llm-server/check_backend_traffic.sh
BACKEND_IP="192.168.0.6"
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$DIR"

line() { printf '\n==== %s ====\n' "$1"; }

line "1. Backend(${BACKEND_IP}) からのリクエスト件数（コンテナ全ログ）"
total="$(docker logs shopai-fast-llm 2>&1 | grep -c "${BACKEND_IP}:")"
echo "${BACKEND_IP} からのアクセスログ行数: ${total}"

line "2. Backend からの最近のリクエスト（末尾15件・エンドポイント/ステータス）"
docker logs shopai-fast-llm 2>&1 | grep "${BACKEND_IP}:" | tail -15 || echo "(なし)"

line "3. エンドポイント別の内訳（Backend発のみ）"
docker logs shopai-fast-llm 2>&1 | grep "${BACKEND_IP}:" \
  | grep -oE '"(GET|POST) /v1/[a-z/]+' | sort | uniq -c | sort -rn || echo "(なし)"

line "4. 直近のアクセスログ全体（送信元IP問わず・末尾10件）"
docker logs shopai-fast-llm 2>&1 | grep -E '"(GET|POST) /v1/' | tail -10 || echo "(なし)"

line "5. ファイアウォール: 8000番が Backend 限定になっているか"
echo "--- DOCKER-USER チェーン ---"
iptables -L DOCKER-USER -n --line-numbers 2>/dev/null || echo "(iptables参照不可)"
echo "--- ufw status ---"
ufw status verbose 2>/dev/null | grep -E '8000|Status' || echo "(ufw無効/参照不可)"

line "6. shopai-docker-fw.service（再起動後もFW維持されるか）"
systemctl is-enabled shopai-docker-fw.service 2>&1
systemctl is-active  shopai-docker-fw.service 2>&1

echo
echo "==== 判定 ===="
echo "項目1 の件数が1以上＝バックエンドが実際にこのLLMノードを呼んでいる証拠。"
echo "項目3 に /v1/chat/completions が並べば、LLMサーバとして機能中。"
