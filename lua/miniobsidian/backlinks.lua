local M = {}

local fs = require("miniobsidian.fs")
local path_policy = require("miniobsidian.path")
local wikilink = require("miniobsidian.wikilink")
local uv = vim.uv or vim.loop

local function strip_md(value)
  return value:gsub("%.md$", "")
end

local function same_path(left, right)
  if not left or not right then
    return false
  end
  return (uv.fs_realpath(left) or path_policy.normalize(left))
    == (uv.fs_realpath(right) or path_policy.normalize(right))
end

local function note_lines(path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and same_path(vim.api.nvim_buf_get_name(bufnr), path) then
      return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    end
  end
  return fs.read_lines(path)
end

local function scan_lines(lines, callback)
  local markdown = require("miniobsidian.markdown")
  markdown.transform(table.concat(lines, "\n"), function(line, visible, number)
    markdown.wikilinks(line, visible, function(inner, column)
      callback(inner, number, column, line)
    end)
  end)
end

---@param target_path? string Absolute path; defaults to the current buffer.
---@return table[]|nil items
---@return string|nil error
function M.collect(target_path)
  local core = require("miniobsidian")
  target_path = target_path or vim.api.nvim_buf_get_name(0)
  if target_path == "" or target_path:lower():sub(-3) ~= ".md" then
    return nil, "Current buffer is not a Markdown note"
  end
  if not core.in_vault(target_path) then
    return nil, "Current note is not in the active vault"
  end

  -- 反向链接本身需要扫描所有文件，因此同时强制刷新路径列表，避免遗漏外部新建笔记。
  local notes = core.get_all_notes(true)
  local target
  for _, path in ipairs(notes) do
    if same_path(path, target_path) then
      target = path
      break
    end
  end
  if not target then
    return nil, "Current note is not saved or does not exist"
  end

  local resolved_target, resolve_err = path_policy.resolve(core.config.vault_path, target, { allow_absolute = true })
  if not resolved_target then
    return nil, tostring(resolve_err)
  end
  local target_id = strip_md(resolved_target.logical)
  local target_basename = target_id:match("([^/]+)$") or target_id
  local resolution_cache = {}
  local items = {}

  local function points_to_target(parsed)
    local candidate = parsed.target
    local expected = candidate:find("/", 1, true) and target_id or target_basename
    if candidate:lower() ~= expected:lower() then
      return false
    end
    if resolution_cache[candidate] == nil then
      local resolved = wikilink.resolve(parsed, notes, core.config.vault_path)
      resolution_cache[candidate] = resolved and resolved.path or false
    end
    return resolution_cache[candidate] ~= false and same_path(resolution_cache[candidate], target)
  end

  for _, note_path in ipairs(notes) do
    local lines, read_err = note_lines(note_path)
    if not lines then
      return nil, "Failed to read note " .. note_path .. ": " .. tostring(read_err)
    end
    scan_lines(lines, function(inner, line_number, column, line)
      local parsed = wikilink.parse(inner)
      if parsed and points_to_target(parsed) then
        items[#items + 1] = {
          file = note_path,
          pos = { line_number, column },
          line = line,
          text = note_path .. ":" .. line_number .. ":" .. line,
        }
      end
    end)
  end

  table.sort(items, function(left, right)
    if left.file == right.file then
      if left.pos[1] == right.pos[1] then
        return left.pos[2] < right.pos[2]
      end
      return left.pos[1] < right.pos[1]
    end
    return left.file < right.file
  end)
  return items
end

---@param target_path? string Absolute path; defaults to the current buffer.
function M.open(target_path)
  local core = require("miniobsidian")
  local items, err = M.collect(target_path)
  if not items then
    core.notify(err, vim.log.levels.ERROR)
    return
  end
  if #items == 0 then
    core.notify("No backlinks for the current note", vim.log.levels.INFO)
    return
  end

  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker or not snacks.picker.pick then
    core.notify("Viewing backlinks requires the snacks.nvim plugin", vim.log.levels.ERROR)
    return
  end

  local current = path_policy.resolve(core.config.vault_path, target_path or vim.api.nvim_buf_get_name(0), {
    allow_absolute = true,
  })
  local title = current and strip_md(current.logical) or core.note_stem(target_path or vim.api.nvim_buf_get_name(0))
  snacks.picker.pick({
    title = " Backlinks: " .. title,
    cwd = core.config.vault_path,
    items = items,
    format = "file",
    preview = "file",
    confirm = "jump",
  })
end

return M
