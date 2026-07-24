-- ============================================================
-- 文件名：daily.lua
-- 模块职责：每日笔记（Daily Note）功能。
--   • 按 config.daily_date_format 格式化今天的日期作为文件名
--   • 在 vault_path/dailies_folder/ 下创建或打开对应笔记
--   • 新文件自动写入 frontmatter（与 note.lua 风格一致）
-- 依赖关系：miniobsidian（config、invalidate_cache）
-- 对外 API：M.open_today()
-- ============================================================

local M = {}
local path_policy = require("miniobsidian.path")

--- 打开（或创建）今日每日笔记。
-- 行为：
--   1. 计算今日日期文件名：os.date(cfg.daily_date_format)
--   2. 确保 vault_path/dailies_folder/ 目录存在（自动 mkdir -p）
--   3. 若文件不存在：写入带 frontmatter 的初始内容，并使补全 cache 失效
--   4. 用 vim.cmd("edit ...") 打开文件（vim.schedule 确保不在锁定上下文中调用）
---@param opts? { switch_root?: boolean }
function M.open_today(opts)
  opts = opts or {}
  local core = require("miniobsidian")
  local cfg = core.config

  local date_str = os.date(cfg.daily_date_format) --[[@as string]]
  local logical = cfg.dailies_folder == "" and (date_str .. ".md") or (cfg.dailies_folder .. "/" .. date_str .. ".md")
  local resolved, resolve_err = path_policy.resolve(cfg.vault_path, logical)
  if not resolved then
    vim.notify("[miniobsidian] Daily Note 路径不安全: " .. tostring(resolve_err), vim.log.levels.ERROR)
    return
  end
  local path = resolved.path
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")

  local is_new = vim.fn.filereadable(path) == 0
  if is_new then
    local lines = {
      "---",
      "title: " .. core.yaml_quote(date_str),
      "date: " .. date_str,
      "tags: [daily]",
      "---",
      "",
      "# " .. date_str,
      "",
    }
    local ok, err = pcall(function()
      local f = io.open(path, "w")
      if not f then
        error("无法创建文件: " .. path)
      end
      f:write(table.concat(lines, "\n"))
      f:close()
    end)
    if not ok then
      core.notify("创建每日笔记失败: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    core.invalidate_cache()
  end

  vim.schedule(function()
    vim.cmd("edit " .. vim.fn.fnameescape(path))

    if is_new then
      local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      for i, line in ipairs(buf_lines) do
        if line:match("^# ") then
          vim.api.nvim_win_set_cursor(0, { math.min(i + 1, #buf_lines), 0 })
          break
        end
      end
    end

    core.after_note_open(path, opts)
  end)
end

return M
