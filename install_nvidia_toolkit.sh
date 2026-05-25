#!/usr/bin/env bash
# NVIDIA Container Toolkit を導入し、Docker から GPU が見えるか確認するスクリプト。
# 実行: sudo bash ~/shopai-llm-server/install_nvidia_toolkit.sh
set -euo pipefail

echo "[1/4] NVIDIA Container Toolkit リポジトリを登録..."
cat > /etc/apt/sources.list.d/nvidia-container-toolkit.list <<'LISTEOF'
deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/$(ARCH) /
#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/experimental/deb/$(ARCH) /
LISTEOF
echo "  -> /etc/apt/sources.list.d/nvidia-container-toolkit.list を作成"

echo "[2/4] apt 更新 & nvidia-container-toolkit インストール..."
apt-get update
apt-get install -y nvidia-container-toolkit

echo "[3/4] Docker ランタイムに NVIDIA を登録して再起動..."
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

echo "[4/4] Docker から GPU が見えるか確認 (Blackwell sm_120 ゲート)..."
set +e
docker run --rm --gpus all ubuntu nvidia-smi
rc=$?
set -e
echo
if [ "$rc" -eq 0 ]; then
  echo "✅ 成功: Docker内から RTX 5070 Ti が見えました。次は vLLM 起動へ。"
else
  echo "❌ GPU確認に失敗 (rc=$rc)。上のエラー出力を貼ってください。"
fi
