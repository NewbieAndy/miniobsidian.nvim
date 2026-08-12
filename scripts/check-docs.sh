#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

docs="README.md README.en.md doc/miniobsidian.txt doc/miniobsidian.zh.txt"
config_keys="vaults_parent default_vault auto_discover sync_obsidian_config notes_subdir dailies_folder daily_template daily_default_content templates_folder attachments_folder daily_date_format picker_scope change_cwd_on_switch checkbox_states note_id_func on_vault_switch after_note_open"

for file in $docs; do
  for key in $config_keys; do
    if ! grep -Fq "$key" "$file"; then
      echo "$file: missing configuration key $key" >&2
      exit 1
    fi
  done
done

commands=$(sed -n 's/.*nvim_create_user_command("\([^"]*\)".*/\1/p' plugin/miniobsidian.lua)
for file in $docs; do
  for command in $commands; do
    if ! grep -Fq "$command" "$file"; then
      echo "$file: missing user command $command" >&2
      exit 1
    fi
  done
done

legacy_patterns="miniobsidian.cli external_change_mode watch_external_changes miniobsidian.agent_result ObsidianAudit"
for pattern in $legacy_patterns; do
  if grep -Fq "$pattern" $docs; then
    echo "formal documentation contains removed API: $pattern" >&2
    exit 1
  fi
done

"${NVIM:-nvim}" --headless -u NONE -i NONE --cmd 'set runtimepath^=.' \
  -c 'helptags doc' \
  -c 'help miniobsidian-config' \
  -c 'help miniobsidian-zh-config' \
  -c qa

echo "documentation contract: ok"
