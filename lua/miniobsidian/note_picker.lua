local M = {}
local path_policy = require("miniobsidian.path")

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

---@param query? string
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
