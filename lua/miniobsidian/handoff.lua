local M = {
  last_request = nil,
}

local SCHEMA_VERSION = "miniobsidian.agent-handoff/v1"

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

local function request_id(mode)
  return ("handoff-%s-%s"):format(mode, tostring(vim.uv.hrtime()))
end

local function current_note(mode, opts)
  local core = require("miniobsidian")
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or not core.in_vault(path) then
    return nil, fail(opts, "PATH_OUTSIDE_VAULT", "当前 buffer 不是活跃 Vault 内的笔记")
  end
  local resolved, err = require("miniobsidian.path").resolve(core.config.vault_path, path, {
    allow_absolute = true,
  })
  if not resolved or not resolved.logical:match("%.md$") then
    return nil, fail(opts, "INVALID_ARGUMENT", err or "当前 buffer 不是 Markdown 笔记")
  end
  local modified = vim.api.nvim_get_option_value("modified", { buf = buf })
  if mode == "update" and modified then
    return nil, fail(opts, "UNSAVED_BUFFER", "更新型 Agent handoff 前必须先保存当前笔记")
  end
  return {
    buf = buf,
    logical = resolved.logical,
    modified = modified,
  }
end

local function selected_content(note, opts)
  local first = opts.line1
  local last = opts.line2
  if not opts.has_range then
    if not note.modified then
      return {
        scope = "none",
        start_line = vim.NIL,
        end_line = vim.NIL,
        text = vim.NIL,
        line_count = 0,
      }
    end
    first = 1
    last = vim.api.nvim_buf_line_count(note.buf)
  end
  local lines = vim.api.nvim_buf_get_lines(note.buf, first - 1, last, false)
  return {
    scope = opts.has_range and "selection" or "buffer",
    start_line = first,
    end_line = last,
    text = table.concat(lines, "\n"),
    line_count = #lines,
  }
end

local function preview(payload)
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {
    "# Agent Handoff Preview",
    "",
    ("request_id: %s"):format(payload.request_id),
    ("mode: %s"):format(payload.mode),
    ("skill: %s"):format(payload.agent.skill),
    ("path: %s"):format(payload.source.path),
    ("revision: %s"):format(payload.source.revision),
    ("intent: %s"):format(payload.intent),
    ("content_scope: %s"):format(payload.context.scope),
    "",
  }
  if payload.context.text ~= vim.NIL then
    vim.list_extend(lines, vim.split(payload.context.text, "\n", { plain = true }))
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  local width = math.max(50, math.min(100, vim.o.columns - 4))
  local height = math.max(8, math.min(#lines, vim.o.lines - 4))
  return vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    title = " Agent handoff ",
  })
end

local function dispatch(payload, opts)
  local core = require("miniobsidian")
  local handler = core.config.agent and core.config.agent.handler
  if type(handler) ~= "function" then
    return fail(opts, "AGENT_HANDLER_UNAVAILABLE", "请在 agent.handler 中配置 Agent 集成回调")
  end
  local ok, result = pcall(handler, vim.deepcopy(payload))
  if not ok then
    return fail(opts, "AGENT_HANDLER_FAILED", tostring(result), { request_id = payload.request_id })
  end
  if result == false then
    return fail(opts, "AGENT_HANDLER_FAILED", "Agent handler 拒绝了 handoff", {
      request_id = payload.request_id,
    })
  end
  M.last_request = vim.deepcopy(payload)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "MiniObsidianAgentHandoff",
    data = {
      request_id = payload.request_id,
      mode = payload.mode,
      path = payload.source.path,
    },
  })
  local dispatched = {
    status = "dispatched",
    request_id = payload.request_id,
    handler_result = result,
  }
  finish(opts, dispatched, nil)
  return true
end

local function confirm_and_dispatch(payload, opts)
  local config = require("miniobsidian").config.agent
  local has_content = payload.context.scope ~= "none"
  local should_confirm = has_content
    and (config.confirm_content or payload.context.line_count >= config.large_selection_lines)
  if not should_confirm then
    return dispatch(payload, opts)
  end
  local win = preview(payload)
  vim.ui.select({ "Send", "Cancel" }, {
    prompt = ("Send %s handoff %s?"):format(payload.mode, payload.request_id),
  }, function(choice)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if choice ~= "Send" then
      finish(opts, { status = "cancelled", request_id = payload.request_id }, nil)
      return
    end
    dispatch(payload, opts)
  end)
  return true
end

local function build(mode, intent, command_opts, opts)
  opts = opts or {}
  if mode ~= "analyze" and mode ~= "update" then
    return fail(opts, "INVALID_ARGUMENT", "handoff mode 必须是 analyze 或 update")
  end
  if type(intent) ~= "string" or vim.trim(intent) == "" then
    return fail(opts, "INVALID_ARGUMENT", "Agent handoff 必须包含明确意图")
  end
  local cli = require("miniobsidian.cli")
  if not cli.available("note.get") or (mode == "update" and not cli.available("note.patch")) then
    local required = mode == "update" and "note.get 和 note.patch" or "note.get"
    return fail(opts, "CAPABILITY_UNSUPPORTED", "Agent handoff 需要 obs-cli " .. required .. " capability")
  end
  local note = current_note(mode, opts)
  if not note then
    return false
  end
  local context = selected_content(note, {
    has_range = command_opts and command_opts.range and command_opts.range > 0,
    line1 = command_opts and command_opts.line1 or 1,
    line2 = command_opts and command_opts.line2 or 1,
  })
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
      fail(opts, err.code or "CLI_EXEC_FAILED", err.message or "读取笔记快照失败", err.details)
      return
    end
    local data = envelope.data or {}
    local snapshot = data.note or {}
    local vault = data.vault or {}
    if
      type(vault.id) ~= "string"
      or type(snapshot.revision) ~= "string"
      or type(snapshot.path) ~= "string"
      or snapshot.path ~= note.logical
    then
      fail(opts, "CLI_INVALID_JSON", "note.get 返回的 Vault ID、path 或 revision 无效")
      return
    end
    if
      mode == "update"
      and (not vim.api.nvim_buf_is_valid(note.buf) or vim.api.nvim_get_option_value("modified", { buf = note.buf }))
    then
      fail(opts, "UNSAVED_BUFFER", "buffer 在 handoff 构建期间发生变化，已停止更新请求")
      return
    end
    local id = request_id(mode)
    local payload = {
      schema_version = SCHEMA_VERSION,
      request_id = id,
      mode = mode,
      intent = vim.trim(intent),
      vault = { id = vault.id },
      source = {
        path = note.logical,
        revision = snapshot.revision,
        buffer_modified = note.modified,
      },
      context = context,
      permissions = {
        allow_vault_scan = false,
        read_paths = { note.logical },
        write_paths = mode == "update" and { note.logical } or {},
      },
      agent = {
        skill = mode == "update" and "obsidian-safe-note-update" or "obsidian-knowledge-synthesis",
        required_capabilities = mode == "update" and { "note.get", "note.patch" } or { "note.get" },
      },
    }
    confirm_and_dispatch(payload, opts)
  end)
  return true
end

---@param mode "analyze"|"update"
---@param intent? string
---@param command_opts? table
---@param opts? table
---@return boolean
function M.handoff(mode, intent, command_opts, opts)
  if intent and vim.trim(intent) ~= "" then
    return build(mode, intent, command_opts, opts)
  end
  vim.ui.input({ prompt = ("Agent %s intent: "):format(mode) }, function(value)
    if not value or vim.trim(value) == "" then
      finish(opts, { status = "cancelled" }, nil)
      return
    end
    build(mode, value, command_opts, opts)
  end)
  return true
end

return M
