-- ============================================================
-- 文件名：note_picker.lua
-- 模块职责：基于 snacks.nvim 提供笔记快速切换（quick_switch）与全文搜索
--           （search）的封装。当 snacks 不可用时通过通知提示用户。
-- 依赖关系：miniobsidian（config、notify）、miniobsidian.path
-- 对外 API：M.quick_switch()、M.search(query?)
-- ============================================================
local M = {}
local path_policy = require("miniobsidian.path")

--- 计算 picker 的搜索根目录。
-- 根据 picker_scope 决定使用整个 Vault 还是仅 notes_subdir。
-- 解析失败时通过通知报错并返回 nil。
---@return string|nil 搜索根目录的绝对路径
local function notes_dir()
  local cfg = require("miniobsidian").config
  local scope = cfg.picker_scope == "vault" and "" or (cfg.notes_subdir or "")
  local resolved, err = path_policy.resolve(cfg.vault_path, scope, { allow_empty = true })
  if not resolved then
    require("miniobsidian").notify("笔记目录不安全: " .. tostring(err), vim.log.levels.ERROR)
    return nil
  end
  return resolved.path
end

--- 通过 snacks.picker.files 模糊查找并打开 Markdown 笔记。
function M.quick_switch()
  local directory = notes_dir()
  if not directory then
    return
  end
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker or not snacks.picker.files then
    require("miniobsidian").notify("需要 snacks.nvim 插件", vim.log.levels.ERROR)
    return
  end
  snacks.picker.files({ title = "  Notes", cwd = directory, dirs = { directory }, ft = { "md" }, hidden = false })
end

--- 通过 snacks.picker.grep + ripgrep 全文搜索 Markdown 笔记。
---@param query? string 可选的初始搜索词
function M.search(query)
  local directory = notes_dir()
  if not directory then
    return
  end
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker or not snacks.picker.grep then
    require("miniobsidian").notify("需要 snacks.nvim 插件", vim.log.levels.ERROR)
    return
  end
  snacks.picker.grep({
    title = " Notes",
    cwd = directory,
    dirs = { directory },
    search = query,
    cmd = "rg",
    hidden = false,
    glob = "*.md",
  })
end

return M
