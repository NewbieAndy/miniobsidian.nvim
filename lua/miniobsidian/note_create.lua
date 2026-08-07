local M = {}
local path_policy = require("miniobsidian.path")

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
  vim.fn.mkdir(vim.fn.fnamemodify(target.path, ":h"), "p")
  return target.path
end

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

---@param dir string
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
