#!/bin/sh
# 模块测试归属检查脚本
# 职责：确保 lua/miniobsidian/ 下的每个模块都有对应的测试文件，
#       并统计测试用例数量不低于阈值。
# 退出码：0 表示检查通过，非 0 表示模块与测试映射不一致。
set -eu

# 切换到仓库根目录
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

# 模块到测试文件的映射（多个模块可共用同一 spec，但会被统计到 owned_count）
module_tests="
checkbox:checkbox_spec.lua
backlinks:backlinks_spec.lua
completion:completion_spec.lua
config_sync:daily_spec.lua
daily:daily_spec.lua
datetime:template_spec.lua
explorer:explorer_spec.lua
fs:fs_spec.lua
health:health_spec.lua
image:image_spec.lua
init:init_spec.lua
link:link_spec.lua
markdown:markdown_spec.lua
markdown_link:markdown_link_spec.lua
note:note_spec.lua
note_create:note_spec.lua
note_move:note_move_spec.lua
note_picker:note_spec.lua
path:path_spec.lua
template:template_spec.lua
vault:vault_spec.lua
wikilink:wikilink_spec.lua
plugin:plugin_spec.lua
"

# 检查每个模块对应的测试文件是否存在
for mapping in $module_tests; do
  module=${mapping%%:*}
  test_file=${mapping#*:}
  if [ ! -f "tests/$test_file" ]; then
    echo "module $module has no test owner: tests/$test_file is missing" >&2
    exit 1
  fi
done

# 统计模块数与有测试归属的模块数是否一致
module_count=$(find lua/miniobsidian -maxdepth 1 -name '*.lua' | wc -l | tr -d ' ')
owned_count=$(printf '%s\n' $module_tests | sed '/^$/d' | grep -v '^plugin:' | wc -l | tr -d ' ')
if [ "$module_count" -ne "$owned_count" ]; then
  echo "module test ownership is stale: $module_count modules, $owned_count owners" >&2
  exit 1
fi

# 统计 it(...) 测试用例总数，确保不低于阈值
test_count=$(awk '/^[[:space:]]*it\(/ { count += 1 } END { print count + 0 }' tests/*_spec.lua)
if [ "$test_count" -lt 65 ]; then
  echo "test inventory regressed below 65 cases: $test_count" >&2
  exit 1
fi

echo "module test ownership: $owned_count modules, $test_count cases"
