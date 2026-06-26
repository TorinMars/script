#!/bin/sh

set -e

# 确保当前目录是 Git 仓库
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "当前目录不是 Git 仓库，请在项目根目录执行。"
  exit 1
fi

# 获取 hook 路径，兼容普通仓库和 worktree
HOOK_PATH="$(git rev-parse --git-path hooks/prepare-commit-msg)"

mkdir -p "$(dirname "$HOOK_PATH")"

cat > "$HOOK_PATH" <<'EOF'
#!/bin/sh

echo "运行开始:$1"

# 检查提交消息是否以 "Merge" 开头或以 "noCheck" 开头
if [ -n "$1" ] && (grep -q "^Merge" "$1" || grep -q "^noCheck" "$1"); then
  echo "提交消息为合并操作或无需检查，正常退出。"
  exit 0
fi

# 获取当前分支名称
branch_name=$(git symbolic-ref --short HEAD)

output=$(mvn validate 2>&1)
status=$?

# Check the status of Maven validate
if [ $status -ne 0 ]; then
  echo "MVN 验证失败，请查看详细日志。"
  echo "$output"
  exit 1
fi

# 提取分支名称中的编号（假设分支名称格式为 feature/T234242 或 bugfix/T234242 等）
issue_number=$(echo "$branch_name" | grep -oE 'T[0-9]+')

# 检查是否找到了 issue_number
if [ -z "$issue_number" ]; then
  echo "分支必须包含TaskId的信息 格式: feature_T3241234_taskDesc"
  exit 0
else
  # 替换所有暂存文件中的 TORIN_PERF 为 issue_number
  staged_files=$(git diff --cached --name-only --diff-filter=ACM)
  for file in $staged_files; do
    if [ -f "$file" ]; then
      if grep -q "TORIN_PERF" "$file"; then
        sed -i.bak "s/TORIN_PERF/$issue_number/g" "$file"
        rm -f "${file}.bak"
        git add "$file"
        echo "已替换文件 $file 中的 TORIN_PERF 为 $issue_number"
      fi
    fi
  done

  # 如果找到了 issue_number，则将其添加到提交消息前面
  sed -i.bak -e "1s/^/$issue_number: /" "$1"
  rm -f "${1}.bak"
fi
EOF

chmod +x "$HOOK_PATH"

echo "prepare-commit-msg hook 已写入并设置执行权限：$HOOK_PATH"
