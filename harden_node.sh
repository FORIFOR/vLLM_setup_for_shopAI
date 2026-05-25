#!/usr/bin/env bash
# GPU ノード仕上げ:
#  (1) ufw でホストの incoming を既定 deny にし SSH のみ許可（Ollama:11434 等も保護）
#  (2) Docker公開ポート8000は ufw を迂回するため DOCKER-USER で Backend(192.168.0.6) 限定に制限
#      （reboot でも効くよう systemd oneshot で永続化）
#  (3) 自動サスペンドをシステムレベルで無効化（24/7サーバ化）
# 実行: sudo bash ~/shopai-llm-server/harden_node.sh
set -uo pipefail

BACKEND_IP="192.168.0.6"
VLLM_PORT="8000"

echo "###################################################"
echo "# (1) ufw: incoming 既定 deny / SSH(22) のみ許可"
echo "###################################################"
ufw allow 22/tcp comment 'SSH'
ufw allow from ${BACKEND_IP} to any port ${VLLM_PORT} proto tcp comment 'ShopAI Backend -> vLLM (non-docker path)'
ufw default deny incoming
ufw default allow outgoing
ufw --force enable
echo "[適用後]"
ufw status verbose

echo
echo "###################################################"
echo "# (2) DOCKER-USER: 公開ポート ${VLLM_PORT} を Backend 限定に"
echo "###################################################"
# 永続化用の適用スクリプトを設置（冪等）
cat > /usr/local/sbin/shopai-docker-fw.sh <<'FWEOF'
#!/usr/bin/env bash
set -e
BACKEND_IP="192.168.0.6"
VLLM_PORT="8000"
# 既存の同種ルールを除去（冪等化）
while iptables -C DOCKER-USER -p tcp --dport ${VLLM_PORT} -j DROP 2>/dev/null; do
  iptables -D DOCKER-USER -p tcp --dport ${VLLM_PORT} -j DROP
done
while iptables -C DOCKER-USER -p tcp -s ${BACKEND_IP} --dport ${VLLM_PORT} -j RETURN 2>/dev/null; do
  iptables -D DOCKER-USER -p tcp -s ${BACKEND_IP} --dport ${VLLM_PORT} -j RETURN
done
# -I は先頭挿入。DROP を先に入れ、その上に RETURN(許可) を積む
iptables -I DOCKER-USER -p tcp --dport ${VLLM_PORT} -j DROP
iptables -I DOCKER-USER -p tcp -s ${BACKEND_IP} --dport ${VLLM_PORT} -j RETURN
FWEOF
chmod 0755 /usr/local/sbin/shopai-docker-fw.sh
/usr/local/sbin/shopai-docker-fw.sh

# boot 時に再適用（DOCKER-USER は docker 起動時に作られる）
cat > /etc/systemd/system/shopai-docker-fw.service <<'UNITEOF'
[Unit]
Description=Restrict vLLM docker port to ShopAI backend (DOCKER-USER)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/shopai-docker-fw.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNITEOF
systemctl daemon-reload
systemctl enable shopai-docker-fw.service
echo "[DOCKER-USER 現在のルール]"
iptables -L DOCKER-USER -n --line-numbers

echo
echo "###################################################"
echo "# (3) 自動サスペンド無効化"
echo "###################################################"
echo "[GNOME(AC)アイドルサスペンドは既に 'nothing'。システムの sleep ターゲットを mask]"
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
echo "[確認(=masked になっていればOK)]"
systemctl is-enabled sleep.target suspend.target hibernate.target hybrid-sleep.target 2>&1 || true

echo
echo "✅ 仕上げ完了"
echo "   - 8000番: 192.168.0.6 からのみ到達可（127.0.0.1 と 自ホスト 192.168.0.15 のローカルテストは引き続き可）"
echo "   - SSH(22) は維持・AnyDeskは外向き接続なので影響なし"
echo "   - suspend は自動/手動とも無効（戻す: sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target）"
