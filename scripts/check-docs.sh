#!/bin/sh
# 文档一致性检查脚本
# 职责：验证所有正式文档（README、help）包含每个配置项和用户命令，
#       并确保已删除的 API 不再出现在文档中；最后重新生成 helptags。
# 退出码：0 表示检查通过，非 0 表示文档与实现不一致。
set -eu

# 切换到仓库根目录
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

# 需要检查的文档文件
docs="README.md README.en.md doc/miniobsidian.txt doc/miniobsidian.zh.txt"
# 所有用户可见的配置键
config_keys="vaults_parent default_vault auto_discover sync_obsidian_config notes_subdir dailies_folder daily_template daily_default_content templates_folder attachments_folder daily_date_format picker_scope change_cwd_on_switch checkbox_states note_id_func on_vault_switch after_note_open"

# 检查每个配置键是否都出现在各文档中
for file in $docs; do
  for key in $config_keys; do
    if ! grep -Fq "$key" "$file"; then
      echo "$file: missing configuration key $key" >&2
      exit 1
    fi
  done
done

# 从 plugin/miniobsidian.lua 提取所有用户命令，并检查是否都出现在各文档中
commands=$(sed -n 's/.*nvim_create_user_command("\([^"]*\)".*/\1/p' plugin/miniobsidian.lua)
for file in $docs; do
  for command in $commands; do
    if ! grep -Fq "$command" "$file"; then
      echo "$file: missing user command $command" >&2
      exit 1
    fi
  done
done

# 检查已移除的 API 是否仍残留在文档中
legacy_patterns="miniobsidian.cli external_change_mode watch_external_changes miniobsidian.agent_result ObsidianAudit"
for pattern in $legacy_patterns; do
  if grep -Fq "$pattern" $docs; then
    echo "formal documentation contains removed API: $pattern" >&2
    exit 1
  fi
done

# 重新生成 Vim 帮助标签
"${NVIM:-nvim}" --headless -u NONE -i NONE --cmd 'set runtimepath^=.' \
  -c 'helptags doc' \
  -c 'help miniobsidian-config' \
  -c 'help miniobsidian-zh-config' \
  -c qa

echo "documentation contract: ok"
