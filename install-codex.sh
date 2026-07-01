#!/usr/bin/env bash

set -e

echo "======== Codex CLI 安装脚本开始 ========"

if [ "$(id -u)" -eq 0 ]; then
  echo "当前是 root 用户"
else
  echo "当前不是 root 用户，后续会使用 sudo"
fi

echo ""
echo "1. 检查系统类型..."

if [ -f /etc/os-release ]; then
  . /etc/os-release
  echo "系统: $PRETTY_NAME"
else
  echo "无法识别系统，仅支持 Ubuntu / Debian"
  exit 1
fi

case "$ID" in
  ubuntu|debian)
    echo "系统支持: $ID"
    ;;
  *)
    echo "当前脚本主要支持 Ubuntu / Debian，你的系统是: $ID"
    exit 1
    ;;
esac

echo ""
echo "2. 更新软件源并安装基础依赖..."

if [ "$(id -u)" -eq 0 ]; then
  apt update
  apt install -y curl wget git ca-certificates gnupg build-essential
else
  sudo apt update
  sudo apt install -y curl wget git ca-certificates gnupg build-essential
fi

echo ""
echo "3. 安装 Node.js LTS..."

if command -v node >/dev/null 2>&1; then
  NODE_VERSION=$(node -v)
  echo "检测到已安装 Node.js: $NODE_VERSION"
else
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
  if [ "$(id -u)" -eq 0 ]; then
    apt install -y nodejs
  else
    sudo apt install -y nodejs
  fi
fi

echo ""
echo "4. 检查 Node.js 和 npm..."

node -v
npm -v

echo ""
echo "5. 安装 Codex CLI..."

if [ "$(id -u)" -eq 0 ]; then
  npm install -g @openai/codex@latest
else
  sudo npm install -g @openai/codex@latest
fi

echo ""
echo "6. 检查 Codex CLI..."

if command -v codex >/dev/null 2>&1; then
  codex --version || true
  echo ""
  echo "Codex CLI 安装成功"
else
  echo "Codex CLI 安装后未找到 codex 命令"
  echo "请检查 npm 全局 bin 路径："
  npm bin -g || true
  exit 1
fi

echo ""
echo "======== 安装完成 ========"
echo "你可以运行以下命令启动 Codex："
echo ""
echo "  codex"
echo ""
echo "首次使用时，通常需要按提示登录 OpenAI / ChatGPT 账号。"
