#!/usr/bin/env bash

set -euo pipefail

echo "======== AI CLI 初始化脚本开始 ========"

export PATH="$HOME/.local/bin:$PATH"

WWW_ROOT="/www/wwwroot"
BT_PANEL_DIR="/www/server/panel"
BT_DATA_DIR="$BT_PANEL_DIR/data"
SCRIPT_REPO="git@github.com:TorinMars/script.git"
APP_PLATFORM_REPO="git@github.com:TorinMars/app_platform.git"
MAIN_REPO="git@github.com:TorinMars/main.git"
MAIN_CONFIG_FILE="$WWW_ROOT/main/config/main.properties"
MAIN_ENCRYPTED_CONFIG_FILE="$WWW_ROOT/main/config/main.properties.encrypt"
MAIN_CONFIG_CRYPTO_SCRIPT="$WWW_ROOT/main/script/python/config_crypto.py"

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

read_from_tty() {
  PROMPT="$1"
  DEFAULT_VALUE="${2:-}"
  VALUE=""

  if [ -r /dev/tty ]; then
    if [ -n "$DEFAULT_VALUE" ]; then
      read -r -p "$PROMPT [$DEFAULT_VALUE]: " VALUE < /dev/tty
      printf '%s\n' "${VALUE:-$DEFAULT_VALUE}"
    else
      read -r -p "$PROMPT: " VALUE < /dev/tty
      printf '%s\n' "$VALUE"
    fi
  else
    printf '%s\n' "$DEFAULT_VALUE"
  fi
}

read_secret_from_tty() {
  PROMPT="$1"
  VALUE=""

  if [ -r /dev/tty ]; then
    read -r -s -p "$PROMPT: " VALUE < /dev/tty
    echo "" > /dev/tty
    printf '%s\n' "$VALUE"
  else
    printf '\n'
  fi
}

show_npm_global_bin() {
  NPM_PREFIX=$(npm config get prefix 2>/dev/null || true)
  if [ -n "$NPM_PREFIX" ]; then
    echo "$NPM_PREFIX/bin"
  fi
}

load_main_properties() {
  if [ ! -f "$MAIN_CONFIG_FILE" ]; then
    return
  fi

  while IFS='=' read -r RAW_KEY RAW_VALUE || [ -n "$RAW_KEY" ]; do
    KEY=$(printf '%s' "$RAW_KEY" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    VALUE=$(printf '%s' "${RAW_VALUE:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$VALUE" in
      \"*\")
        VALUE="${VALUE#\"}"
        VALUE="${VALUE%\"}"
        ;;
      \'*\')
        VALUE="${VALUE#\'}"
        VALUE="${VALUE%\'}"
        ;;
    esac

    case "$KEY" in
      ''|\#*|';'*)
        continue
        ;;
      bt.panel.port)
        CONFIG_BT_PORT="$VALUE"
        ;;
      bt.panel.safe_path)
        CONFIG_BT_SAFE_PATH="$VALUE"
        ;;
      bt.panel.password)
        CONFIG_BT_PASSWORD="$VALUE"
        ;;
      ANTHROPIC_BASE_URL)
        CONFIG_ANTHROPIC_BASE_URL="$VALUE"
        ;;
      ANTHROPIC_AUTH_TOKEN)
        CONFIG_ANTHROPIC_AUTH_TOKEN="$VALUE"
        ;;
      ANTHROPIC_MODEL)
        CONFIG_ANTHROPIC_MODEL="$VALUE"
        ;;
      ANTHROPIC_DEFAULT_OPUS_MODEL)
        CONFIG_ANTHROPIC_DEFAULT_OPUS_MODEL="$VALUE"
        ;;
      ANTHROPIC_DEFAULT_SONNET_MODEL)
        CONFIG_ANTHROPIC_DEFAULT_SONNET_MODEL="$VALUE"
        ;;
      ANTHROPIC_DEFAULT_HAIKU_MODEL)
        CONFIG_ANTHROPIC_DEFAULT_HAIKU_MODEL="$VALUE"
        ;;
      CLAUDE_CODE_SUBAGENT_MODEL)
        CONFIG_CLAUDE_CODE_SUBAGENT_MODEL="$VALUE"
        ;;
      CLAUDE_CODE_EFFORT_LEVEL)
        CONFIG_CLAUDE_CODE_EFFORT_LEVEL="$VALUE"
        ;;
    esac
  done < "$MAIN_CONFIG_FILE"
}

decrypt_main_config_if_needed() {
  echo ""
  echo "7. 解密并读取 main.properties 配置..."

  if [ -f "$MAIN_CONFIG_FILE" ]; then
    echo "检测到明文配置: $MAIN_CONFIG_FILE"
  elif [ -f "$MAIN_ENCRYPTED_CONFIG_FILE" ] && [ -f "$MAIN_CONFIG_CRYPTO_SCRIPT" ]; then
    echo "未找到明文配置，开始解密: $MAIN_ENCRYPTED_CONFIG_FILE"
    python3 "$MAIN_CONFIG_CRYPTO_SCRIPT" decrypt
  elif [ -f "$MAIN_ENCRYPTED_CONFIG_FILE" ]; then
    echo "找到加密配置，但缺少解密脚本: $MAIN_CONFIG_CRYPTO_SCRIPT"
  else
    echo "未找到 main.properties 或 main.properties.encrypt，后续缺失配置会提示输入。"
  fi

  CONFIG_BT_PORT=""
  CONFIG_BT_SAFE_PATH=""
  CONFIG_BT_PASSWORD=""
  CONFIG_ANTHROPIC_BASE_URL=""
  CONFIG_ANTHROPIC_AUTH_TOKEN=""
  CONFIG_ANTHROPIC_MODEL=""
  CONFIG_ANTHROPIC_DEFAULT_OPUS_MODEL=""
  CONFIG_ANTHROPIC_DEFAULT_SONNET_MODEL=""
  CONFIG_ANTHROPIC_DEFAULT_HAIKU_MODEL=""
  CONFIG_CLAUDE_CODE_SUBAGENT_MODEL=""
  CONFIG_CLAUDE_CODE_EFFORT_LEVEL=""
  load_main_properties

  if [ -f "$MAIN_CONFIG_FILE" ]; then
    echo "配置读取完成。"
  fi
}

set_timezone() {
  echo ""
  echo "2. 设置时区为 Asia/Shanghai..."

  CURRENT_TIMEZONE=""
  if command -v timedatectl >/dev/null 2>&1; then
    CURRENT_TIMEZONE=$(timedatectl show -p Timezone --value 2>/dev/null || true)
  elif [ -f /etc/timezone ]; then
    CURRENT_TIMEZONE=$(tr -d '\r\n' < /etc/timezone)
  fi

  if [ "$CURRENT_TIMEZONE" = "Asia/Shanghai" ]; then
    echo "时区已是 Asia/Shanghai，跳过设置。"
    date
    return
  fi

  if command -v timedatectl >/dev/null 2>&1 && run_as_root timedatectl set-timezone Asia/Shanghai; then
    :
  else
    run_as_root ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    echo "Asia/Shanghai" | run_as_root tee /etc/timezone >/dev/null
  fi

  date
}

install_base_dependencies() {
  echo ""
  echo "3. 更新软件源并安装基础依赖..."

  MISSING_PACKAGES=""
  for PACKAGE_NAME in curl wget git ca-certificates gnupg build-essential openssh-client age; do
    if ! dpkg -s "$PACKAGE_NAME" >/dev/null 2>&1; then
      MISSING_PACKAGES="$MISSING_PACKAGES $PACKAGE_NAME"
    fi
  done

  if [ -z "$MISSING_PACKAGES" ]; then
    echo "基础依赖已安装，跳过 apt 操作。"
    return
  fi

  run_as_root apt update
  run_as_root apt install -y $MISSING_PACKAGES
}

install_bt_panel() {
  echo ""
  echo "4. 安装宝塔 Linux 面板..."

  if command -v bt >/dev/null 2>&1 || [ -d "$BT_PANEL_DIR" ]; then
    echo "检测到宝塔面板已安装，跳过安装。"
    return
  fi

  BT_INSTALL_SCRIPT=$(mktemp)
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://download.bt.cn/install/install_panel.sh -o "$BT_INSTALL_SCRIPT"
  else
    wget -O "$BT_INSTALL_SCRIPT" https://download.bt.cn/install/install_panel.sh
  fi

  if [ -r /dev/tty ]; then
    run_as_root bash "$BT_INSTALL_SCRIPT" ed8484bec < /dev/tty
  else
    run_as_root bash "$BT_INSTALL_SCRIPT" ed8484bec
  fi
  rm -f "$BT_INSTALL_SCRIPT"
}

normalize_bt_safe_path() {
  SAFE_PATH="$1"
  SAFE_PATH="${SAFE_PATH#/}"
  SAFE_PATH="${SAFE_PATH%/}"
  printf '/%s\n' "$SAFE_PATH"
}

configure_bt_panel() {
  echo ""
  echo "8. 配置宝塔面板端口、安全入口和密码..."

  BT_PORT="${CONFIG_BT_PORT:-}"
  BT_SAFE_PATH="${CONFIG_BT_SAFE_PATH:-}"
  BT_PASSWORD="${CONFIG_BT_PASSWORD:-}"
  CURRENT_BT_PORT=""
  CURRENT_BT_SAFE_PATH=""

  if [ -f "$BT_DATA_DIR/port.pl" ]; then
    CURRENT_BT_PORT=$(tr -d '\r\n' < "$BT_DATA_DIR/port.pl")
  fi

  if [ -f "$BT_DATA_DIR/admin_path.pl" ]; then
    CURRENT_BT_SAFE_PATH=$(tr -d '\r\n' < "$BT_DATA_DIR/admin_path.pl")
  fi

  if [ -n "$BT_SAFE_PATH" ]; then
    BT_SAFE_PATH=$(normalize_bt_safe_path "$BT_SAFE_PATH")
  fi

  if [ -f "$BT_DATA_DIR/port.pl" ] && [ -f "$BT_DATA_DIR/admin_path.pl" ] &&
    { [ -z "$BT_PORT" ] || [ "$BT_PORT" = "$CURRENT_BT_PORT" ]; } &&
    { [ -z "$BT_SAFE_PATH" ] || [ "$BT_SAFE_PATH" = "$CURRENT_BT_SAFE_PATH" ]; } &&
    [ -z "$BT_PASSWORD" ]; then
    echo "检测到宝塔端口和安全入口已配置，跳过宝塔配置。"
    echo "  端口: $CURRENT_BT_PORT"
    echo "  安全入口: $CURRENT_BT_SAFE_PATH"
    return
  fi

  if [ -z "$BT_PORT" ]; then
    BT_PORT=$(read_from_tty "请输入宝塔面板端口" "${CURRENT_BT_PORT:-7800}")
  fi

  if [ -z "$BT_SAFE_PATH" ]; then
    BT_SAFE_PATH=$(read_from_tty "请输入宝塔安全入口" "${CURRENT_BT_SAFE_PATH:-/$(openssl rand -hex 8 2>/dev/null || date +%s)}")
  fi

  if [ -z "$BT_PASSWORD" ]; then
    BT_PASSWORD=$(read_secret_from_tty "请输入宝塔面板密码（留空则跳过密码修改）")
  fi

  BT_SAFE_PATH=$(normalize_bt_safe_path "$BT_SAFE_PATH")

  if ! printf '%s' "$BT_PORT" | grep -Eq '^[0-9]{2,5}$'; then
    echo "宝塔端口必须是 2-5 位数字，当前输入: $BT_PORT"
    exit 1
  fi

  if [ "$BT_PORT" -lt 1 ] || [ "$BT_PORT" -gt 65535 ]; then
    echo "宝塔端口必须在 1-65535 之间，当前输入: $BT_PORT"
    exit 1
  fi

  if ! printf '%s' "$BT_SAFE_PATH" | grep -Eq '^/[A-Za-z0-9._/-]+$' ||
    printf '%s' "$BT_SAFE_PATH" | grep -Eq '//|/\.$|/\.\.$|/\./|/\.\./|/$|^/$'; then
    echo "宝塔安全入口只能包含字母、数字、点、下划线、中划线和路径分隔符，不能为 / 或包含空路径段，当前输入: $BT_SAFE_PATH"
    exit 1
  fi

  run_as_root mkdir -p "$BT_DATA_DIR"
  printf '%s\n' "$BT_PORT" | run_as_root tee "$BT_DATA_DIR/port.pl" >/dev/null
  printf '%s\n' "$BT_SAFE_PATH" | run_as_root tee "$BT_DATA_DIR/admin_path.pl" >/dev/null

  if [ -n "$BT_PASSWORD" ]; then
    BT_PASSWORD_HASH=$(printf '%s' "$BT_PASSWORD" | sha256sum | awk '{print $1}')
    BT_PASSWORD_MARKER="$BT_DATA_DIR/init_sh_password.sha256"

    if [ -f "$BT_PASSWORD_MARKER" ] && [ "$(tr -d '\r\n' < "$BT_PASSWORD_MARKER")" = "$BT_PASSWORD_HASH" ]; then
      echo "宝塔密码已按当前配置设置过，跳过密码修改。"
    else
      PANEL_PYTHON=""
      for PYTHON_BIN in "$BT_PANEL_DIR/pyenv/bin/python" "$BT_PANEL_DIR/pyenv/bin/python3" /usr/bin/python3; do
        if [ -x "$PYTHON_BIN" ]; then
          PANEL_PYTHON="$PYTHON_BIN"
          break
        fi
      done

      if [ -n "$PANEL_PYTHON" ] && [ -f "$BT_PANEL_DIR/tools.py" ]; then
        run_as_root "$PANEL_PYTHON" "$BT_PANEL_DIR/tools.py" panel "$BT_PASSWORD" || {
          echo "宝塔密码自动设置失败，请安装完成后执行 bt 5 手动修改。"
        }
        printf '%s\n' "$BT_PASSWORD_HASH" | run_as_root tee "$BT_PASSWORD_MARKER" >/dev/null
      else
        echo "未找到宝塔 tools.py 或 Python，跳过密码自动修改。"
        echo "请安装完成后执行 bt 5 手动修改。"
      fi
    fi
  fi

  if command -v bt >/dev/null 2>&1; then
    run_as_root bt restart || true
    run_as_root bt default || true
  fi

  echo "宝塔面板配置完成："
  echo "  端口: $BT_PORT"
  echo "  安全入口: $BT_SAFE_PATH"
}

setup_github_ssh_and_clone() {
  echo ""
  echo "6. 生成 GitHub SSH 密钥并克隆项目..."

  if [ -d "$WWW_ROOT/script/.git" ] && [ -d "$WWW_ROOT/app_platform/.git" ] && [ -d "$WWW_ROOT/main/.git" ]; then
    echo "检测到三个项目仓库已存在，跳过 SSH Key 提示和克隆。"
    return
  fi

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  SSH_KEY_FILE="$HOME/.ssh/id_ed25519"
  if [ ! -f "$SSH_KEY_FILE" ]; then
    ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)-$(date +%Y%m%d)" -f "$SSH_KEY_FILE" -N ""
  else
    echo "检测到已有 SSH 密钥: $SSH_KEY_FILE"
  fi

  echo ""
  echo "请将以下公钥添加到 GitHub SSH Keys："
  echo ""
  cat "$SSH_KEY_FILE.pub"
  echo ""
  echo "GitHub SSH 配置地址："
  echo "  https://github.com/settings/keys"
  echo ""

  if [ -r /dev/tty ]; then
    read -r -p "添加完成后按回车继续克隆项目..." _ < /dev/tty
  else
    echo "当前不是交互式终端，无法等待 GitHub SSH Key 配置。"
  fi

  touch "$HOME/.ssh/known_hosts"
  if ! ssh-keygen -F github.com -f "$HOME/.ssh/known_hosts" >/dev/null 2>&1; then
    ssh-keyscan -T 5 -H github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
  fi
  chmod 600 "$SSH_KEY_FILE"
  chmod 644 "$SSH_KEY_FILE.pub"
  chmod 644 "$HOME/.ssh/known_hosts"

  run_as_root mkdir -p "$WWW_ROOT"
  if [ "$(id -u)" -ne 0 ]; then
    run_as_root chown "$(id -u):$(id -g)" "$WWW_ROOT"
  fi
  clone_or_update_repo "$SCRIPT_REPO" "$WWW_ROOT/script"
  clone_or_update_repo "$APP_PLATFORM_REPO" "$WWW_ROOT/app_platform"
  clone_or_update_repo "$MAIN_REPO" "$WWW_ROOT/main"
}

clone_or_update_repo() {
  REPO_URL="$1"
  TARGET_DIR="$2"

  if [ -d "$TARGET_DIR/.git" ]; then
    CURRENT_REMOTE=$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null || true)
    if [ "$CURRENT_REMOTE" = "$REPO_URL" ]; then
      echo "仓库已存在且 remote 正确，跳过: $TARGET_DIR"
      return
    fi
    echo "仓库已存在但 origin 不匹配，跳过: $TARGET_DIR"
    echo "  当前 origin: $CURRENT_REMOTE"
    echo "  期望 origin: $REPO_URL"
    return
  elif [ -e "$TARGET_DIR" ]; then
    echo "目标路径已存在但不是 Git 仓库，无法克隆: $TARGET_DIR"
    exit 1
  else
    git clone "$REPO_URL" "$TARGET_DIR"
  fi
}

configure_claude_deepseek() {
  echo ""
  echo "16. 配置 Claude Code 使用 DeepSeek..."
  echo "优先读取 main.properties 的 ANTHROPIC_* 和 CLAUDE_CODE_* 配置，Token 缺失时再提示输入。"

  CLAUDE_CONFIG_DIR="$HOME/.claude"
  CLAUDE_SETTINGS_FILE="$CLAUDE_CONFIG_DIR/settings.json"
  ANTHROPIC_BASE_URL="${CONFIG_ANTHROPIC_BASE_URL:-https://api.deepseek.com/anthropic}"
  ANTHROPIC_AUTH_TOKEN="${CONFIG_ANTHROPIC_AUTH_TOKEN:-}"
  ANTHROPIC_MODEL="${CONFIG_ANTHROPIC_MODEL:-deepseek-v4-pro[1m]}"
  ANTHROPIC_DEFAULT_OPUS_MODEL="${CONFIG_ANTHROPIC_DEFAULT_OPUS_MODEL:-$ANTHROPIC_MODEL}"
  ANTHROPIC_DEFAULT_SONNET_MODEL="${CONFIG_ANTHROPIC_DEFAULT_SONNET_MODEL:-$ANTHROPIC_MODEL}"
  ANTHROPIC_DEFAULT_HAIKU_MODEL="${CONFIG_ANTHROPIC_DEFAULT_HAIKU_MODEL:-deepseek-v4-flash}"
  CLAUDE_CODE_SUBAGENT_MODEL="${CONFIG_CLAUDE_CODE_SUBAGENT_MODEL:-deepseek-v4-flash}"
  CLAUDE_CODE_EFFORT_LEVEL="${CONFIG_CLAUDE_CODE_EFFORT_LEVEL:-max}"

  if [ -s "$CLAUDE_SETTINGS_FILE" ] &&
    EXPECTED_ANTHROPIC_BASE_URL="$ANTHROPIC_BASE_URL" \
    EXPECTED_ANTHROPIC_AUTH_TOKEN="$ANTHROPIC_AUTH_TOKEN" \
    EXPECTED_ANTHROPIC_MODEL="$ANTHROPIC_MODEL" \
    EXPECTED_ANTHROPIC_DEFAULT_OPUS_MODEL="$ANTHROPIC_DEFAULT_OPUS_MODEL" \
    EXPECTED_ANTHROPIC_DEFAULT_SONNET_MODEL="$ANTHROPIC_DEFAULT_SONNET_MODEL" \
    EXPECTED_ANTHROPIC_DEFAULT_HAIKU_MODEL="$ANTHROPIC_DEFAULT_HAIKU_MODEL" \
    EXPECTED_CLAUDE_CODE_SUBAGENT_MODEL="$CLAUDE_CODE_SUBAGENT_MODEL" \
    EXPECTED_CLAUDE_CODE_EFFORT_LEVEL="$CLAUDE_CODE_EFFORT_LEVEL" \
    node - "$CLAUDE_SETTINGS_FILE" <<'NODE'
const fs = require('fs');
const settingsFile = process.argv[2];
try {
  const settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8'));
  const env = settings.env || {};
  const configured =
    settings.model === process.env.EXPECTED_ANTHROPIC_MODEL &&
    env.ANTHROPIC_BASE_URL === process.env.EXPECTED_ANTHROPIC_BASE_URL &&
    env.ANTHROPIC_AUTH_TOKEN === process.env.EXPECTED_ANTHROPIC_AUTH_TOKEN &&
    env.ANTHROPIC_MODEL === process.env.EXPECTED_ANTHROPIC_MODEL &&
    env.ANTHROPIC_DEFAULT_OPUS_MODEL === process.env.EXPECTED_ANTHROPIC_DEFAULT_OPUS_MODEL &&
    env.ANTHROPIC_DEFAULT_SONNET_MODEL === process.env.EXPECTED_ANTHROPIC_DEFAULT_SONNET_MODEL &&
    env.ANTHROPIC_DEFAULT_HAIKU_MODEL === process.env.EXPECTED_ANTHROPIC_DEFAULT_HAIKU_MODEL &&
    env.CLAUDE_CODE_SUBAGENT_MODEL === process.env.EXPECTED_CLAUDE_CODE_SUBAGENT_MODEL &&
    env.CLAUDE_CODE_EFFORT_LEVEL === process.env.EXPECTED_CLAUDE_CODE_EFFORT_LEVEL;
  process.exit(configured ? 0 : 1);
} catch {
  process.exit(1);
}
NODE
  then
    echo "Claude Code DeepSeek JSON 配置已存在，跳过配置。"
    return
  fi

  if [ -n "$ANTHROPIC_AUTH_TOKEN" ]; then
    echo "已从 main.properties 读取 ANTHROPIC_AUTH_TOKEN。"
  elif [ -r /dev/tty ]; then
    read -r -p "请输入 ANTHROPIC_AUTH_TOKEN / DeepSeek API Token（留空跳过配置）: " ANTHROPIC_AUTH_TOKEN < /dev/tty
  else
    echo "当前不是交互式终端，跳过 DeepSeek Token 配置。"
    echo "如需配置，请在服务器上执行：bash init.sh"
    return
  fi

  if [ -z "$ANTHROPIC_AUTH_TOKEN" ]; then
    echo "未输入 Token，跳过 DeepSeek 配置。"
    return
  fi

  mkdir -p "$CLAUDE_CONFIG_DIR"

  if [ ! -s "$CLAUDE_SETTINGS_FILE" ]; then
    printf '{}\n' > "$CLAUDE_SETTINGS_FILE"
  fi

  ANTHROPIC_BASE_URL="$ANTHROPIC_BASE_URL" \
  ANTHROPIC_AUTH_TOKEN="$ANTHROPIC_AUTH_TOKEN" \
  ANTHROPIC_MODEL="$ANTHROPIC_MODEL" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="$ANTHROPIC_DEFAULT_OPUS_MODEL" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="$ANTHROPIC_DEFAULT_SONNET_MODEL" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$ANTHROPIC_DEFAULT_HAIKU_MODEL" \
  CLAUDE_CODE_SUBAGENT_MODEL="$CLAUDE_CODE_SUBAGENT_MODEL" \
  CLAUDE_CODE_EFFORT_LEVEL="$CLAUDE_CODE_EFFORT_LEVEL" \
  node - "$CLAUDE_SETTINGS_FILE" <<'NODE'
const fs = require('fs');

const settingsFile = process.argv[2];

let settings = {};
try {
  settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8'));
} catch (error) {
  const backupFile = `${settingsFile}.bak.${Date.now()}`;
  fs.copyFileSync(settingsFile, backupFile);
  settings = {};
  console.log(`原 settings.json 不是有效 JSON，已备份到: ${backupFile}`);
}

settings.$schema = settings.$schema || 'https://json.schemastore.org/claude-code-settings.json';
settings.model = process.env.ANTHROPIC_MODEL;
settings.env = {
  ...(settings.env || {}),
  ANTHROPIC_BASE_URL: process.env.ANTHROPIC_BASE_URL,
  ANTHROPIC_AUTH_TOKEN: process.env.ANTHROPIC_AUTH_TOKEN,
  ANTHROPIC_MODEL: process.env.ANTHROPIC_MODEL,
  ANTHROPIC_DEFAULT_OPUS_MODEL: process.env.ANTHROPIC_DEFAULT_OPUS_MODEL,
  ANTHROPIC_DEFAULT_SONNET_MODEL: process.env.ANTHROPIC_DEFAULT_SONNET_MODEL,
  ANTHROPIC_DEFAULT_HAIKU_MODEL: process.env.ANTHROPIC_DEFAULT_HAIKU_MODEL,
  CLAUDE_CODE_SUBAGENT_MODEL: process.env.CLAUDE_CODE_SUBAGENT_MODEL,
  CLAUDE_CODE_EFFORT_LEVEL: process.env.CLAUDE_CODE_EFFORT_LEVEL,
};

fs.writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`);
NODE

  echo "DeepSeek 配置已写入 Claude Code 默认配置文件: $CLAUDE_SETTINGS_FILE"
}

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

set_timezone
install_base_dependencies
install_bt_panel
setup_github_ssh_and_clone
decrypt_main_config_if_needed
configure_bt_panel

echo ""
echo "9. 安装 uv..."

if command -v uv >/dev/null 2>&1; then
  uv --version
  echo "检测到已安装 uv"
else
  UV_INSTALL_SCRIPT=$(mktemp)
  curl -LsSf https://astral.sh/uv/install.sh -o "$UV_INSTALL_SCRIPT"
  sh "$UV_INSTALL_SCRIPT"
  rm -f "$UV_INSTALL_SCRIPT"
fi

echo ""
echo "10. 检查 uv..."

if command -v uv >/dev/null 2>&1; then
  uv --version
  echo "uv 安装成功"
else
  echo "uv 安装后未找到 uv 命令"
  echo "请检查 ~/.local/bin 是否在 PATH 中"
  exit 1
fi

echo ""
echo "11. 安装 Node.js LTS..."

if command -v node >/dev/null 2>&1 && [ "$(node -p 'Number(process.versions.node.split(".")[0])')" -ge 18 ]; then
  NODE_VERSION=$(node -v)
  echo "检测到已安装 Node.js: $NODE_VERSION"
else
  if command -v node >/dev/null 2>&1; then
    echo "检测到 Node.js 版本低于 18，升级到 LTS..."
  fi
  NODE_SETUP_SCRIPT=$(mktemp)
  curl -fsSL https://deb.nodesource.com/setup_lts.x -o "$NODE_SETUP_SCRIPT"
  run_as_root bash "$NODE_SETUP_SCRIPT"
  rm -f "$NODE_SETUP_SCRIPT"
  run_as_root apt install -y nodejs
fi

echo ""
echo "12. 检查 Node.js 和 npm..."

node -v
npm -v

echo ""
echo "13. 安装 Codex CLI 和 Claude Code..."

if command -v codex >/dev/null 2>&1 && command -v claude >/dev/null 2>&1; then
  echo "Codex CLI 和 Claude Code 已安装，跳过 npm 全局安装。"
else
  run_as_root npm install -g @openai/codex@latest @anthropic-ai/claude-code@latest
fi

echo ""
echo "14. 检查 Codex CLI..."

if command -v codex >/dev/null 2>&1; then
  codex --version || true
  echo ""
  echo "Codex CLI 安装成功"
else
  echo "Codex CLI 安装后未找到 codex 命令"
  echo "请检查 npm 全局 bin 路径："
  show_npm_global_bin
  exit 1
fi

echo ""
echo "15. 检查 Claude Code..."

if command -v claude >/dev/null 2>&1; then
  claude --version || true
  echo ""
  echo "Claude Code 安装成功"
else
  echo "Claude Code 安装后未找到 claude 命令"
  echo "请检查 npm 全局 bin 路径："
  show_npm_global_bin
  exit 1
fi

configure_claude_deepseek

echo ""
echo "======== 初始化完成 ========"
echo "你可以运行以下命令启动："
echo ""
echo "  uv"
echo "  codex"
echo "  claude"
echo ""
echo "Codex 首次使用通常需要按提示登录 OpenAI / ChatGPT 账号。"
echo "Claude Code 如已配置 DeepSeek Token，将读取 ~/.claude/settings.json 使用 DeepSeek 三方模型。"
