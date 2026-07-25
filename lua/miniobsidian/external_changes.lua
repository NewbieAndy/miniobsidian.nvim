local M = {}

local uv = vim.uv or vim.loop
local watcher
local debounce_timer
local conflicts = {}
local checking = false
local last_check_ms = 0

M.actions = {
  diff = "查看 buffer ↔ 磁盘 diff",
  keep = "保留 Neovim buffer",
  reload = "重新加载磁盘内容",
}

local function is_markdown_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return false
  end
  local path = vim.api.nvim_buf_get_name(buf)
  return path:lower():sub(-3) == ".md" and require("miniobsidian").in_vault(path)
end

local function disk_text(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local file, err = io.open(path, "r")
  if not file then
    return "", err
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function buffer_text(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local content = table.concat(lines, "\n")
  if vim.api.nvim_get_option_value("endofline", { buf = buf }) then
    content = content .. "\n"
  end
  return content
end

---@param buf integer
---@return string
function M.diff(buf)
  local memory = buffer_text(buf)
  local disk = disk_text(buf)
  return vim.diff(memory, disk, {
    result_type = "unified",
    ctxlen = 3,
  })
end

---@param buf integer
function M.show_diff(buf)
  local ok, result = pcall(M.diff, buf)
  if not ok then
    require("miniobsidian").notify("无法生成外部修改 diff: " .. tostring(result), vim.log.levels.ERROR)
    return
  end
  vim.cmd("botright new")
  local diff_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(diff_buf, "miniobsidian://external-diff/" .. buf)
  vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, vim.split(result, "\n", { plain = true }))
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = diff_buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = diff_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = diff_buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = diff_buf })
  vim.api.nvim_set_option_value("filetype", "diff", { buf = diff_buf })
end

---@param buf integer
---@return boolean
---@return string|nil
function M.before_write(buf)
  local conflict = conflicts[buf]
  if conflict then
    return false,
      "检测到磁盘版本已被外部修改；请先执行 :ObsidianResolveConflict 查看 diff、保留或重新加载"
  end
  return true
end

---@param buf integer
function M.reload(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent! edit!")
  end)
  conflicts[buf] = nil
  require("miniobsidian").invalidate_cache()
end

---@param buf integer
---@param action string
function M.resolve(buf, action)
  if action == M.actions.diff then
    M.show_diff(buf)
  elseif action == M.actions.reload then
    M.reload(buf)
  elseif action == M.actions.keep then
    require("miniobsidian").notify(
      "已保留 Neovim buffer；在解决冲突前写入会被阻止",
      vim.log.levels.WARN
    )
  end
end

---@param buf integer
---@param force? boolean
function M.prompt(buf, force)
  local conflict = conflicts[buf]
  if not conflict or (conflict.prompted and not force) then
    return
  end
  conflict.prompted = true

  local mode = require("miniobsidian").config.external_change_mode
  if mode == "notify" and not force then
    require("miniobsidian").notify("磁盘文件已外部修改: " .. conflict.reason, vim.log.levels.WARN)
    return
  end

  vim.ui.select({ M.actions.diff, M.actions.keep, M.actions.reload }, {
    prompt = "检测到外部修改，选择处理方式:",
  }, function(choice)
    if choice then
      M.resolve(buf, choice)
    end
  end)
end

---@param buf integer
---@param reason string
function M.on_file_changed(buf, reason)
  if not is_markdown_buffer(buf) then
    return
  end

  require("miniobsidian").invalidate_cache()
  local modified = vim.api.nvim_get_option_value("modified", { buf = buf })
  local mode = require("miniobsidian").config.external_change_mode
  local can_reload = not modified and reason ~= "deleted"

  if can_reload and mode == "reload" then
    vim.v.fcs_choice = "reload"
    conflicts[buf] = nil
    return
  end

  -- FileChangedShell 默认 choice 为空，由本模块接管，绝不隐式覆盖 buffer。
  vim.v.fcs_choice = ""
  conflicts[buf] = {
    reason = reason,
    modified = modified,
    prompted = false,
  }
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) then
      M.prompt(buf)
    end
  end)
end

---@param buf integer
function M.after_file_changed(buf)
  if is_markdown_buffer(buf) then
    require("miniobsidian").invalidate_cache()
  end
end

---@param buf integer
function M.clear(buf)
  conflicts[buf] = nil
end

---@param buf integer
---@return table|nil
function M.get_conflict(buf)
  return conflicts[buf]
end

---@param buf integer
---@param reason? string
---@param opts? {prompted?: boolean}
---@return boolean
function M.mark_conflict(buf, reason, opts)
  if not is_markdown_buffer(buf) then
    return false
  end
  opts = opts or {}
  conflicts[buf] = {
    reason = reason or "agent",
    modified = vim.api.nvim_get_option_value("modified", { buf = buf }),
    prompted = opts.prompted == true,
  }
  require("miniobsidian").invalidate_cache()
  return true
end

---Run a throttled native checktime over loaded buffers.
---@param force? boolean
function M.checktime(force)
  local interval = require("miniobsidian").config.external_check_interval_ms or 1000
  local now = uv.hrtime() / 1000000
  if checking or (not force and now - last_check_ms < interval) then
    return
  end
  checking = true
  last_check_ms = now
  vim.schedule(function()
    pcall(vim.cmd, "silent! checktime")
    checking = false
  end)
end

function M.on_fs_event()
  if debounce_timer then
    debounce_timer:stop()
  else
    debounce_timer = uv.new_timer()
  end
  local delay = require("miniobsidian").config.external_watch_debounce_ms or 100
  debounce_timer:start(
    delay,
    0,
    vim.schedule_wrap(function()
      require("miniobsidian").invalidate_cache()
    end)
  )
end

function M.stop_watcher()
  if watcher then
    watcher:stop()
    watcher:close()
    watcher = nil
  end
  if debounce_timer then
    debounce_timer:stop()
    debounce_timer:close()
    debounce_timer = nil
  end
end

---@param vault string
---@return boolean
function M.start_watcher(vault)
  M.stop_watcher()
  if require("miniobsidian").config.watch_external_changes == false or vim.fn.isdirectory(vault) == 0 then
    return false
  end

  watcher = uv.new_fs_event()
  local ok, started = pcall(function()
    return watcher:start(vault, { recursive = true }, function(err)
      if not err then
        M.on_fs_event()
      end
    end)
  end)
  if not ok or started == nil then
    watcher:close()
    watcher = nil
    require("miniobsidian").notify(
      "无法启动 Vault 文件监听，将由 FocusGained/checktime 兜底",
      vim.log.levels.WARN
    )
    return false
  end
  return true
end

---@param group integer
function M.setup_autocmds(group)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_markdown_buffer(buf) then
      vim.api.nvim_set_option_value("autoread", false, { buf = buf })
    end
  end

  vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
    group = group,
    callback = function(ev)
      if ev.event == "FocusGained" then
        -- 跨平台兜底：失效本身是 O(1)，不会在焦点切回时扫描大型 Vault。
        require("miniobsidian").invalidate_cache()
        M.checktime(true)
      elseif is_markdown_buffer(ev.buf) then
        M.checktime(ev.event == "FocusGained")
      end
    end,
  })

  vim.api.nvim_create_autocmd("FileChangedShell", {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      M.on_file_changed(ev.buf, vim.v.fcs_reason)
    end,
  })

  vim.api.nvim_create_autocmd("FileChangedShellPost", {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      M.after_file_changed(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      if is_markdown_buffer(ev.buf) then
        local ok, err = M.before_write(ev.buf)
        if not ok then
          error("[miniobsidian] " .. err)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      if is_markdown_buffer(ev.buf) then
        -- 由 external_change_mode 统一控制，避免用户全局 autoread 绕过冲突策略。
        vim.api.nvim_set_option_value("autoread", false, { buf = ev.buf })
        M.clear(ev.buf)
        require("miniobsidian").invalidate_cache()
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(ev)
      M.clear(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MiniObsidianVaultSwitch",
    callback = function(ev)
      M.start_watcher(ev.data.path)
    end,
  })

  M.start_watcher(require("miniobsidian").config.vault_path)
end

return M
