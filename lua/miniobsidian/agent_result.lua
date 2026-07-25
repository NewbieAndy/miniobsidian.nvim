local M = {
  last_result = nil,
}

local SCHEMA_VERSION = "miniobsidian.agent-result/v1"

M.actions = {
  diff = "查看 Agent diff",
  keep = "保留 Neovim buffer",
  reload = "采用磁盘版本（本地快照保留）",
  merge = "打开手动合并 buffer",
}

local function fail(code, message, details)
  local err = { code = code, message = message, details = details or {} }
  require("miniobsidian").notify(("%s: %s"):format(code, message), vim.log.levels.ERROR)
  return nil, err
end

local function readonly_buffer(name, lines, filetype, hidden)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name .. "/" .. tostring((vim.uv or vim.loop).hrtime()))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", hidden or "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", filetype or "markdown", { buf = buf })
  return buf
end

local function split_text(content)
  return vim.split(content or "", "\n", { plain = true })
end

local function disk_text(path)
  local file, err = io.open(path, "r")
  if not file then
    return nil, err
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function buffer_text(buf)
  local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  if vim.api.nvim_get_option_value("endofline", { buf = buf }) then
    content = content .. "\n"
  end
  return content
end

local function loaded_buffer(path)
  local real = (vim.uv or vim.loop).fs_realpath(path) or path
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local current = vim.api.nvim_buf_get_name(buf)
      if current ~= "" and ((vim.uv or vim.loop).fs_realpath(current) or current) == real then
        return buf
      end
    end
  end
  return nil
end

local function resolve_change(change)
  local core = require("miniobsidian")
  local resolved, err = require("miniobsidian.path").resolve(core.config.vault_path, change.path)
  if not resolved or not resolved.logical:match("%.md$") then
    return nil, err or "changed path is not a Markdown note"
  end
  return resolved
end

local function validate_change(change)
  if
    type(change) ~= "table"
    or type(change.path) ~= "string"
    or type(change.revision_before) ~= "string"
    or type(change.revision_after) ~= "string"
    or type(change.summary) ~= "string"
    or (change.before_content ~= nil and type(change.before_content) ~= "string")
  then
    return false
  end
  if
    not change.revision_before:match("^sha256:[a-f0-9]+$")
    or #change.revision_before ~= 71
    or not change.revision_after:match("^sha256:[a-f0-9]+$")
    or #change.revision_after ~= 71
  then
    return false
  end
  return true
end

local function validate_error(item)
  if
    type(item) ~= "table"
    or type(item.code) ~= "string"
    or item.code == ""
    or type(item.message) ~= "string"
    or item.message == ""
    or type(item.recovery_steps) ~= "table"
    or (item.path ~= nil and type(item.path) ~= "string")
  then
    return false
  end
  for _, step in ipairs(item.recovery_steps) do
    if type(step) ~= "string" or step == "" then
      return false
    end
  end
  return true
end

local function validate(result)
  if
    type(result) ~= "table"
    or result.schema_version ~= SCHEMA_VERSION
    or type(result.request_id) ~= "string"
    or not result.request_id:match("^[A-Za-z0-9._:-]+$")
    or #result.request_id > 128
    or not vim.tbl_contains({ "success", "partial", "failed", "cancelled", "conflict" }, result.status)
    or type(result.summary) ~= "string"
    or type(result.changes) ~= "table"
    or type(result.errors) ~= "table"
  then
    return false
  end
  for _, change in ipairs(result.changes) do
    if not validate_change(change) then
      return false
    end
  end
  for _, item in ipairs(result.errors) do
    if not validate_error(item) then
      return false
    end
  end
  if result.status == "cancelled" and (#result.changes > 0 or #result.errors > 0) then
    return false
  end
  if vim.tbl_contains({ "partial", "failed", "conflict" }, result.status) and #result.errors == 0 then
    return false
  end
  return true
end

function M.summary_lines(result)
  local lines = {
    "# Agent Result",
    "",
    "request_id: " .. result.request_id,
    "status: " .. result.status,
    "summary: " .. result.summary,
    "",
    "## Changed files",
  }
  if #result.changes == 0 then
    lines[#lines + 1] = "- none"
  end
  for _, change in ipairs(result.changes) do
    lines[#lines + 1] = ("- %s: %s"):format(change.path, change.summary)
    lines[#lines + 1] = ("  revision: %s → %s"):format(change.revision_before, change.revision_after)
  end
  if #result.errors > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Recovery checklist"
    for _, item in ipairs(result.errors) do
      lines[#lines + 1] = ("- [%s] %s%s"):format(
        item.code or "UNKNOWN",
        item.path and (item.path .. ": ") or "",
        item.message or "unknown error"
      )
      for _, step in ipairs(item.recovery_steps or {}) do
        lines[#lines + 1] = "  - " .. step
      end
    end
  end
  return lines
end

function M.show_summary(result)
  local buf = readonly_buffer("miniobsidian://agent-result/" .. result.request_id, M.summary_lines(result), "markdown")
  vim.api.nvim_set_current_buf(buf)
  return buf
end

function M.show_last()
  if not M.last_result then
    return fail("AGENT_RESULT_MISSING", "尚未收到 Agent result")
  end
  return M.show_summary(M.last_result), nil
end

local function show_unified(change, memory, disk)
  local diff = vim.diff(memory, disk, { result_type = "unified", ctxlen = 3 })
  local buf = readonly_buffer("miniobsidian://agent-diff/" .. change.path, split_text(diff), "diff")
  vim.api.nvim_set_current_buf(buf)
  return buf
end

local function manual_merge(change, local_content, disk)
  local lines = {
    "<<<<<<< NEOVIM LOCAL",
  }
  vim.list_extend(lines, split_text(local_content))
  lines[#lines + 1] = "======="
  vim.list_extend(lines, split_text(disk))
  lines[#lines + 1] = ">>>>>>> AGENT DISK"
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(
    buf,
    "miniobsidian://agent-merge/" .. change.path .. "/" .. tostring((vim.uv or vim.loop).hrtime())
  )
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_set_current_buf(buf)
  return buf
end

function M.show_three_way(change, buf, disk)
  if type(change.before_content) ~= "string" then
    return fail("AGENT_BASE_MISSING", "dirty buffer 三方比较缺少 Agent 修改前正文", {
      path = change.path,
      recovery_steps = {
        "保留当前 Neovim buffer",
        "从 Agent 结果或版本控制恢复 revision_before",
        "不要重载或写入，直到手动完成比较",
      },
    })
  end
  local local_content = buffer_text(buf)
  vim.cmd("tabnew")
  local local_buf =
    readonly_buffer("miniobsidian://agent-local/" .. change.path, split_text(local_content), "markdown", "hide")
  vim.api.nvim_set_current_buf(local_buf)
  vim.cmd("vsplit")
  local base_buf =
    readonly_buffer("miniobsidian://agent-base/" .. change.path, split_text(change.before_content), "markdown", "hide")
  vim.api.nvim_set_current_buf(base_buf)
  vim.cmd("vsplit")
  local disk_buf = readonly_buffer("miniobsidian://agent-disk/" .. change.path, split_text(disk), "markdown", "hide")
  vim.api.nvim_set_current_buf(disk_buf)
  return {
    local_buf = local_buf,
    base_buf = base_buf,
    disk_buf = disk_buf,
    local_content = local_content,
  }
end

function M.inspect_change(change)
  local resolved, resolve_err = resolve_change(change)
  if not resolved then
    return fail("PATH_OUTSIDE_VAULT", resolve_err, { path = change.path })
  end
  local disk, disk_err = disk_text(resolved.path)
  if not disk then
    return fail("NOTE_NOT_FOUND", "无法读取 Agent 修改后的磁盘文件", {
      path = change.path,
      error = tostring(disk_err),
    })
  end
  local buf = loaded_buffer(resolved.path)
  if not buf then
    local before = type(change.before_content) == "string" and change.before_content or ""
    return { kind = "diff", buffer = show_unified(change, before, disk) }
  end

  local external = require("miniobsidian.external_changes")
  external.mark_conflict(buf, "agent:" .. change.revision_after, { prompted = true })
  local modified = vim.api.nvim_get_option_value("modified", { buf = buf })
  if not modified then
    local memory = buffer_text(buf)
    local diff_buf = show_unified(change, memory, disk)
    vim.ui.select({ M.actions.diff, M.actions.keep, M.actions.reload }, {
      prompt = "Agent 已修改磁盘文件，选择处理方式:",
    }, function(choice)
      if choice == M.actions.diff and vim.api.nvim_buf_is_valid(diff_buf) then
        vim.api.nvim_set_current_buf(diff_buf)
      elseif choice == M.actions.reload then
        readonly_buffer("miniobsidian://agent-local/" .. change.path, split_text(memory), "markdown", "hide")
        external.reload(buf)
      end
    end)
    return { kind = "diff", buffer = diff_buf, source_buffer = buf }
  end

  local view, err = M.show_three_way(change, buf, disk)
  if not view then
    return nil, err
  end
  vim.ui.select({ M.actions.keep, M.actions.reload, M.actions.merge }, {
    prompt = "Agent 与 dirty buffer 冲突；不会自动选择版本:",
  }, function(choice)
    if choice == M.actions.reload then
      external.reload(buf)
    elseif choice == M.actions.merge then
      manual_merge(change, view.local_content, disk)
    end
  end)
  return { kind = "three_way", view = view, source_buffer = buf }
end

---@param result table
---@return table|nil
---@return table|nil
function M.handle(result)
  if not validate(result) then
    return fail("AGENT_RESULT_INVALID", "Agent result 不符合 miniobsidian.agent-result/v1")
  end
  local last = require("miniobsidian.handoff").last_request
  if last and last.request_id ~= result.request_id then
    return fail("AGENT_REQUEST_MISMATCH", "Agent result request_id 与最近 handoff 不一致", {
      expected = last.request_id,
      actual = result.request_id,
    })
  end
  M.last_result = vim.deepcopy(result)

  if result.status == "cancelled" then
    require("miniobsidian").notify("Agent 请求已取消；未执行后续动作")
    return { status = "cancelled", request_id = result.request_id }, nil
  end

  local summary = M.show_summary(result)
  if #result.changes == 0 then
    return { status = result.status, request_id = result.request_id, summary_buffer = summary }, nil
  end

  local function inspect(change)
    if change then
      M.inspect_change(change)
    end
  end
  if #result.changes == 1 then
    inspect(result.changes[1])
  else
    vim.ui.select(result.changes, {
      prompt = "选择要查看的 Agent changed file:",
      format_item = function(change)
        return change.path .. " — " .. change.summary
      end,
    }, inspect)
  end
  return {
    status = result.status,
    request_id = result.request_id,
    summary_buffer = summary,
    changed_files = #result.changes,
  },
    nil
end

return M
