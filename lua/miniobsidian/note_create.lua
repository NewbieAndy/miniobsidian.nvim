-- ============================================================
-- 文件名：note_create.lua
-- 模块职责：提供笔记创建的核心实现，包括根据标题生成安全路径、
--           写入 frontmatter、打开 buffer 并触发 after_note_open 回调。
--           被 note.lua 暴露为 public API，也被 plugin/miniobsidian.lua
--           中的用户命令直接调用。
-- 依赖关系：miniobsidian（config、notify、update_note_cache、after_note_open）、
--           miniobsidian.path、miniobsidian.fs
-- 对外 API：M.new_note(title, opts)、M.new_note_in_dir(dir)、
--           M.new_note_here()、M.create(title, dir, opts)
-- ============================================================
local M = {}
local path_policy = require("miniobsidian.path")

--- 根据标题与目标目录计算新笔记的绝对路径。
-- 先由 note_id_func 生成文件名 ID，再解析目标目录，最后组合成 Vault 相对
-- 逻辑路径并二次校验。目录不存在时会自动创建。
---@param title string 笔记标题
---@param target_dir string|nil 目标目录（绝对路径或 Vault 相对路径）
---@param explicit_id string|nil 显式指定的 Note ID，优先级高于 note_id_func
---@return string|nil path 安全的目标绝对路径
---@return string|nil err 错误信息
local function note_path(title, target_dir, explicit_id)
  local cfg = require("miniobsidian").config
  local id = explicit_id or cfg.note_id_func(title)
  local directory, err
  if target_dir then
    directory, err = path_policy.resolve(cfg.vault_path, target_dir, { allow_absolute = true, allow_empty = true })
  else
    directory, err = path_policy.resolve(cfg.vault_path, cfg.notes_subdir, { allow_empty = true })
  end
  if not directory then
    return nil, err
  end

  local logical = directory.logical == "" and (id .. ".md") or (directory.logical .. "/" .. id .. ".md")
  local target, target_err = path_policy.resolve(cfg.vault_path, logical)
  if not target then
    return nil, target_err
  end
  -- 确保父目录存在，避免后续写入失败
  vim.fn.mkdir(vim.fn.fnamemodify(target.path, ":h"), "p")
  return target.path
end

--- 交互式或命令行创建新笔记。
-- 未提供标题时弹出 vim.ui.input 让用户输入。
---@param title? string
---@param opts? {switch_root?: boolean, note_id?: string}
function M.new_note(title, opts)
  opts = opts or {}
  if title and title ~= "" then
    M.create(title, nil, opts)
    return
  end
  vim.ui.input({ prompt = "新笔记标题: " }, function(input)
    if input and input ~= "" then
      M.create(input, nil, opts)
    end
  end)
end

--- 在指定绝对目录下创建新笔记。
-- 会先校验目录是否位于当前 Vault 内。
---@param dir string 目标目录绝对路径
function M.new_note_in_dir(dir)
  local core = require("miniobsidian")
  dir = dir:gsub("/+$", "")
  if not core.in_vault(dir) then
    core.notify("目标目录不在当前 vault 内: " .. dir, vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = "新笔记标题: " }, function(input)
    if input and input ~= "" then
      M.create(input, dir)
    end
  end)
end

--- 在文件树当前焦点目录创建新笔记。
-- 无法识别文件树焦点时回退到默认 notes_subdir，并给出提示。
function M.new_note_here()
  local core = require("miniobsidian")
  local dir = require("miniobsidian.explorer").current_dir()
  if dir then
    dir = dir:gsub("/+$", "")
    if not core.in_vault(dir) then
      core.notify("目标目录不在当前 vault 内: " .. dir, vim.log.levels.WARN)
      return
    end
  else
    local resolved, err = path_policy.resolve(core.config.vault_path, core.config.notes_subdir, { allow_empty = true })
    if not resolved then
      core.notify("默认笔记目录不安全: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    dir = resolved.path
    core.notify("未检测到文件树焦点，将创建到默认目录: " .. core.config.notes_subdir)
  end

  vim.ui.input({ prompt = "新笔记标题: " }, function(input)
    if input and input ~= "" then
      M.create(input, dir)
    end
  end)
end

--- 实际执行笔记创建与打开。
-- 生成安全路径后使用 no-replace 语义写入 frontmatter，更新缓存，
-- 打开 buffer 并将光标移到标题下一行，最后触发 after_note_open 回调。
---@param title string
---@param dir? string
---@param opts? {switch_root?: boolean, note_id?: string}
function M.create(title, dir, opts)
  opts = opts or {}
  local path, path_err = note_path(title, dir, opts.note_id)
  if not path then
    require("miniobsidian").notify("笔记路径不安全: " .. tostring(path_err), vim.log.levels.ERROR)
    return
  end

  local core = require("miniobsidian")
  -- 构造默认 frontmatter：title、date、tags 以及一级标题
  local frontmatter = table.concat({
    "---",
    "title: " .. core.yaml_quote(title),
    "date: " .. os.date(core.config.daily_date_format),
    "tags: []",
    "---",
    "",
    "# " .. title,
    "",
  }, "\n")

  -- 使用排他创建，避免覆盖已有笔记
  local is_new, create_err = require("miniobsidian.fs").create_exclusive(path, frontmatter)
  if is_new == nil then
    core.notify("创建笔记失败: " .. tostring(create_err), vim.log.levels.ERROR)
    return
  end
  if is_new then
    core.update_note_cache(path)
  end

  vim.schedule(function()
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    if is_new then
      -- 新建笔记时将光标定位到标题下一行
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      for index, line in ipairs(lines) do
        if line:match("^# ") then
          vim.api.nvim_win_set_cursor(0, { math.min(index + 1, #lines), 0 })
          break
        end
      end
    end
    core.after_note_open(path, opts)
  end)
end

return M
