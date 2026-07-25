local M = {}

local function finish(opts, result, err)
  if opts and opts.on_complete then
    vim.schedule(function()
      opts.on_complete(result, err)
    end)
  end
end

local function fail(opts, code, message, details)
  local err = { code = code, message = message, details = details or {} }
  require("miniobsidian").notify(("%s: %s"):format(code, message), vim.log.levels.ERROR)
  finish(opts, nil, err)
  return false
end

local function current_note(opts)
  local core = require("miniobsidian")
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or not core.in_vault(path) then
    return nil, fail(opts, "PATH_OUTSIDE_VAULT", "当前 buffer 不是活跃 Vault 内的笔记")
  end
  if vim.api.nvim_get_option_value("modified", { buf = buf }) then
    return nil, fail(opts, "UNSAVED_BUFFER", "请先保存当前笔记，再执行移动")
  end
  local resolved, err = require("miniobsidian.path").resolve(core.config.vault_path, path, {
    allow_absolute = true,
  })
  if not resolved or not resolved.logical:match("%.md$") then
    return nil, fail(opts, "INVALID_ARGUMENT", err or "当前 buffer 不是 Markdown 笔记")
  end
  return { buf = buf, path = path, logical = resolved.logical }
end

local function target_note(input, opts)
  if type(input) ~= "string" or input == "" then
    return nil, fail(opts, "INVALID_ARGUMENT", "目标路径不能为空")
  end
  if not input:match("%.md$") then
    input = input .. ".md"
  end
  local core = require("miniobsidian")
  local resolved, err = require("miniobsidian.path").resolve(core.config.vault_path, input)
  if not resolved then
    return nil, fail(opts, "PATH_OUTSIDE_VAULT", err)
  end
  return resolved
end

local function note_revision(envelope)
  local data = envelope and envelope.data
  local note = data and data.note
  return note and note.revision
end

local function plan_data(envelope)
  local data = envelope and envelope.data
  if type(data) ~= "table" or type(data.plan_hash) ~= "string" or type(data.plan) ~= "table" then
    return nil
  end
  return data
end

---@param data table
---@return string[]
function M.format_plan(data)
  local lines = {
    "# Obsidian Move Dry Run",
    "",
    "plan_hash: " .. data.plan_hash,
    "",
  }
  for _, change in ipairs(data.plan.changes or {}) do
    lines[#lines + 1] = ("## %s %s"):format(change.action or "change", change.target or "")
    local details = change.details or {}
    lines[#lines + 1] = "expected_revision: " .. (details.expected_revision or "")
    lines[#lines + 1] = "revision_after: " .. (details.revision_after or "")
    for _, edit in ipairs(details.link_edits or {}) do
      lines[#lines + 1] = ("- link: %s → %s"):format(
        edit.before or edit.original or "?",
        edit.after or edit.updated or "?"
      )
    end
    lines[#lines + 1] = ""
  end
  for _, risk in ipairs((data.plan and data.plan.risks) or {}) do
    lines[#lines + 1] = "RISK: " .. risk
  end
  return lines
end

---@param data table
---@return integer|nil window
function M.preview(data)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.format_plan(data))
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "diff", { buf = buf })
  local width = math.max(50, math.min(100, vim.o.columns - 4))
  local height = math.max(8, math.min(#M.format_plan(data), vim.o.lines - 4))
  return vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    title = " obs-cli move dry-run ",
  })
end

local function close_preview(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

local function sync_buffer(note, target, opts, receipt)
  if not vim.api.nvim_buf_is_valid(note.buf) then
    return fail(opts, "BUFFER_MISSING", "移动成功，但原 buffer 已关闭", { receipt = receipt })
  end
  if vim.api.nvim_get_option_value("modified", { buf = note.buf }) then
    return fail(opts, "UNSAVED_BUFFER", "移动成功，但 buffer 在 apply 期间被修改；未自动重载", {
      receipt = receipt,
    })
  end
  vim.api.nvim_buf_set_name(note.buf, target.path)
  vim.api.nvim_buf_call(note.buf, function()
    vim.cmd("silent edit!")
  end)
  require("miniobsidian").invalidate_cache()
  finish(opts, receipt, nil)
  return true
end

local function apply(note, target, revision, plan, opts)
  if
    vim.api.nvim_buf_get_name(note.buf) ~= note.path
    or vim.api.nvim_get_option_value("modified", { buf = note.buf })
  then
    fail(opts, "UNSAVED_BUFFER", "buffer 在确认后发生变化，已停止 apply")
    return
  end
  local core = require("miniobsidian")
  require("miniobsidian.cli").call({
    "note",
    "move",
    note.logical,
    target.logical,
    "--vault",
    core.config.vault_path,
    "--if-match",
    revision,
    "--if-plan-hash",
    plan.plan_hash,
    "--output",
    "json",
  }, { operation = "note.move", mutating = true }, function(envelope, err)
    if err then
      fail(opts, err.code or "CLI_EXEC_FAILED", err.message or "移动失败", err.details)
      return
    end
    local receipt = envelope.data and envelope.data.receipt
    if type(receipt) ~= "table" or receipt.plan_hash ~= plan.plan_hash or receipt.target ~= target.logical then
      fail(opts, "CLI_INVALID_JSON", "移动回执与授权计划不一致")
      return
    end
    sync_buffer(note, target, opts, receipt)
  end)
end

local function plan(note, target, revision, opts)
  local core = require("miniobsidian")
  require("miniobsidian.cli").call({
    "note",
    "move",
    note.logical,
    target.logical,
    "--vault",
    core.config.vault_path,
    "--if-match",
    revision,
    "--dry-run",
    "--output",
    "json",
  }, { operation = "note.move" }, function(envelope, err)
    if err then
      fail(opts, err.code or "CLI_EXEC_FAILED", err.message or "dry-run 失败", err.details)
      return
    end
    local data = plan_data(envelope)
    if not data then
      fail(opts, "CLI_INVALID_JSON", "move dry-run 缺少 plan_hash 或 changes")
      return
    end
    local win = M.preview(data)
    vim.ui.select({ "Apply", "Cancel" }, {
      prompt = ("Move %s → %s?"):format(note.logical, target.logical),
    }, function(choice)
      close_preview(win)
      if choice ~= "Apply" then
        finish(opts, { status = "cancelled", plan_hash = data.plan_hash }, nil)
        return
      end
      apply(note, target, revision, data, opts)
    end)
  end)
end

---@param target? string
---@param opts? {on_complete?: fun(result: table|nil, err: table|nil)}
---@return boolean started
function M.move_current(target, opts)
  opts = opts or {}
  local cli = require("miniobsidian.cli")
  if not cli.available("note.get") or not cli.available("note.move") then
    return fail(opts, "CAPABILITY_UNSUPPORTED", "需要 obs-cli note.get 和 note.move capability")
  end
  local note = current_note(opts)
  if not note then
    return false
  end
  if not target or target == "" then
    vim.ui.input({ prompt = "Move target (Vault-relative): " }, function(value)
      if not value or value == "" then
        finish(opts, { status = "cancelled" }, nil)
        return
      end
      M.move_current(value, opts)
    end)
    return true
  end
  local resolved = target_note(target, opts)
  if not resolved then
    return false
  end
  local core = require("miniobsidian")
  cli.call({
    "note",
    "get",
    note.logical,
    "--vault",
    core.config.vault_path,
    "--output",
    "json",
  }, { operation = "note.get" }, function(envelope, err)
    if err then
      fail(opts, err.code or "CLI_EXEC_FAILED", err.message or "读取 revision 失败", err.details)
      return
    end
    local revision = note_revision(envelope)
    if type(revision) ~= "string" or revision == "" then
      fail(opts, "CLI_INVALID_JSON", "note.get 未返回 revision")
      return
    end
    plan(note, resolved, revision, opts)
  end)
  return true
end

---@param opts? {on_complete?: fun(result: table|nil, err: table|nil)}
---@return boolean
function M.audit(opts)
  opts = opts or {}
  local cli = require("miniobsidian.cli")
  if not cli.available("note.list") then
    return fail(opts, "CAPABILITY_UNSUPPORTED", "需要 obs-cli note.list capability")
  end
  local core = require("miniobsidian")
  cli.call({
    "note",
    "list",
    "--vault",
    core.config.vault_path,
    "--output",
    "json",
  }, { operation = "note.list" }, function(envelope, err)
    if err then
      fail(opts, err.code or "CLI_EXEC_FAILED", err.message or "只读审计失败", err.details)
      return
    end
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = vim.split(vim.json.encode(envelope.data), "\n", { plain = true })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("filetype", "json", { buf = buf })
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_set_current_buf(buf)
    finish(opts, envelope.data, nil)
  end)
  return true
end

return M
