# script

服务器初始化脚本，用于完成新服务器基础初始化、安装宝塔面板、配置 GitHub SSH、克隆项目，并安装 uv、Codex CLI 和 Claude Code。

## 一行命令执行

在 Ubuntu / Debian 服务器上执行：

```bash
curl -fsSL https://raw.githubusercontent.com/TorinMars/script/main/init.sh | bash
```

如果当前用户不是 root，脚本会自动使用 `sudo` 安装系统依赖、宝塔面板和全局 npm 包。

脚本按幂等方式设计，可重复执行；已完成的步骤会跳过，不会重复生成 SSH Key、重复克隆项目或重复写入 Claude Code 配置。

脚本会优先解密并读取 `/www/wwwroot/main/config/main.properties`。如果明文不存在但存在 `/www/wwwroot/main/config/main.properties.encrypt`，会先调用 `/www/wwwroot/main/script/python/config_crypto.py decrypt` 解密。

配置文件缺少对应值时，执行过程中才会提示输入：

- 宝塔面板端口
- 宝塔安全入口
- 宝塔面板密码
- DeepSeek API Token

脚本会生成 GitHub SSH 公钥并输出 `https://github.com/settings/keys`，将公钥添加到 GitHub 后，按回车继续克隆项目。

## 安装内容

- 基础依赖：`curl`、`wget`、`git`、`ca-certificates`、`gnupg`、`build-essential`、`age`
- 时区：`Asia/Shanghai`
- 宝塔 Linux 面板
- GitHub SSH Key
- 项目仓库：`git@github.com:TorinMars/script.git`
- 项目仓库：`git@github.com:TorinMars/app_platform.git`
- 项目仓库：`git@github.com:TorinMars/main.git`
- uv
- Node.js LTS
- Codex CLI：`@openai/codex@latest`
- Claude Code：`@anthropic-ai/claude-code@latest`
- Claude Code DeepSeek 默认 JSON 配置

## 初始化顺序

1. 检查系统类型
2. 设置时区为上海东八区
3. 安装基础依赖
4. 安装宝塔 Linux 面板
5. 生成 SSH Key，等待用户添加到 GitHub
6. 克隆 `script`、`app_platform` 和 `main` 到 `/www/wwwroot`
7. 解密并读取 `/www/wwwroot/main/config/main.properties`
8. 设置宝塔端口、安全入口和密码
9. 安装 uv、Node.js LTS、Codex CLI、Claude Code
10. 配置 Claude Code 使用 DeepSeek

## main.properties 配置

配置模板在 `/www/wwwroot/main/config/main.properties.example`：

```properties
bt.panel.port=7800
bt.panel.safe_path=/change-me
bt.panel.password=
ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
ANTHROPIC_AUTH_TOKEN=
ANTHROPIC_MODEL=deepseek-v4-pro[1m]
ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4-pro[1m]
ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-pro[1m]
ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash
CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash
CLAUDE_CODE_EFFORT_LEVEL=max
```

填写后加密：

```bash
cd /www/wwwroot/main
cp config/main.properties.example config/main.properties
vi config/main.properties
python3 script/python/config_crypto.py encrypt --force
```

## Claude Code DeepSeek 默认配置

脚本会写入当前用户的 `~/.claude/settings.json`，不会修改 `~/.bashrc` 或 `~/.zshrc`：

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "model": "deepseek-v4-pro[1m]",
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "main.properties 中的 ANTHROPIC_AUTH_TOKEN",
    "ANTHROPIC_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash",
    "CLAUDE_CODE_SUBAGENT_MODEL": "deepseek-v4-flash",
    "CLAUDE_CODE_EFFORT_LEVEL": "max"
  }
}
```

如果已有 `~/.claude/settings.json`，脚本会保留原有配置并合并 DeepSeek 相关字段；如果原文件不是有效 JSON，会先备份再重建。

## 安装后使用

```bash
uv
codex
claude
```

Codex 首次使用通常需要按提示登录 OpenAI / ChatGPT 账号。Claude Code 如已配置 DeepSeek Token，将读取 `~/.claude/settings.json` 使用 DeepSeek 三方模型。
