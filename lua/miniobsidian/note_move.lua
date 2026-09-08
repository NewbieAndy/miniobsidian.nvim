local M = {}

local uv = vim.uv or vim.loop
local fs = require("miniobsidian.fs")
local path_policy = require("miniobsidian.path")
local wikilink = require("miniobsidian.wikilink")
local markdown = require("miniobsidian.markdown")

---Stable error codes exposed for tests and programmatic handling.
M.error_codes = {
  SAVE_BEFORE_MOVE = "SAVE_BEFORE_MOVE",
  BUFFER_OCCUPIED = "BUFFER_OCCUPIED",
  BUFFER_OPEN_IN_WINDOW = "BUFFER_OPEN_IN_WINDOW",
  STALE_BUFFER = "STALE_BUFFER",
  NOT_A_NOTE_FILE = "NOT_A_NOTE_FILE",
  NO_ACTIONABLE_NOTE = "NO_ACTIONABLE_NOTE",
  TARGET_NOT_STRING = "TARGET_NOT_STRING",
  TARGET_NOT_MD = "TARGET_NOT_MD",
  ALREADY_AT_TARGET = "ALREADY_AT_TARGET",
  TARGET_EXISTS = "TARGET_EXISTS",
  READ_NOTE_FAILED = "READ_NOTE_FAILED",
  BUFFER_RENAME_FAILED = "BUFFER_RENAME_FAILED",
  UNSAVED_PEERS = "UNSAVED_PEERS",
  CREATE_DIRECTORY_FAILED = "CREATE_DIRECTORY_FAILED",
  MOVE_FAILED = "MOVE_FAILED",
  RENAME_FAILED = "RENAME_FAILED",
  UPDATE_REFERENCES_FAILED = "UPDATE_REFERENCES_FAILED",
  ROLLBACK_INCOMPLETE = "ROLLBACK_INCOMPLETE",
  RENAME_NOT_STRING = "RENAME_NOT_STRING",
  RENAME_EMPTY = "RENAME_EMPTY",
  RENAME_ONLY_FILENAME = "RENAME_ONLY_FILENAME",
}

local E = M.error_codes

local function coded_error(code, message)
  return code .. ": " .. message
end

local function strip_md(value)
  return value:gsub("%.md$", "")
end

local function basename(value)
  return path_policy.normalize(value):match("([^/]+)$")
end

local function dirname(value)
  return path_policy.normalize(value):match("^(.*)/[^/]+$") or ""
end

local function same_path(left, right)
  local left_real = path_policy.realpath(left)
  local right_real = path_policy.realpath(right)
  return left_real ~= nil and left_real == right_real
end

local function save_source_buffer(source)
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buffer) then
      local name = vim.api.nvim_buf_get_name(buffer)
      if name ~= "" and same_path(name, source) then
        if vim.api.nvim_buf_is_loaded(buffer) and vim.bo[buffer].modified then
          local ok, err = pcall(vim.api.nvim_buf_call, buffer, function()
            vim.cmd("silent noautocmd write")
          end)
          if not ok then
            return nil, coded_error(E.SAVE_BEFORE_MOVE, "Failed to save note before moving: " .. tostring(err))
          end
        end
        return buffer
      end
    end
  end
  return nil
end

local function release_stale_target_buffer(target_buffer, source_buffer)
  if target_buffer == -1 or target_buffer == source_buffer then
    return true
  end
  if not vim.api.nvim_buf_is_valid(target_buffer) then
    return true
  end
  if vim.bo[target_buffer].modified then
    return nil, coded_error(E.BUFFER_OCCUPIED, "Failed to move: target path is occupied by another buffer")
  end
  if vim.api.nvim_buf_is_loaded(target_buffer) and #vim.fn.win_findbuf(target_buffer) > 0 then
    return nil, coded_error(E.BUFFER_OPEN_IN_WINDOW, "Failed to move: target path is open in another window")
  end
  local deleted, delete_err = pcall(vim.api.nvim_buf_delete, target_buffer, { force = false })
  if not deleted then
    return nil, coded_error(E.STALE_BUFFER, "Failed to clean up stale buffer for target path: " .. tostring(delete_err))
  end
  return true
end

local function modified_vault_buffer(vault, source)
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buffer) and vim.bo[buffer].modified then
      local name = vim.api.nvim_buf_get_name(buffer)
      local resolved = name ~= "" and path_policy.resolve(vault, name, { allow_absolute = true }) or nil
      if resolved and not same_path(name, source) and name:match("%.md$") then
        return name
      end
    end
  end
  return nil
end

local function resolve_source(vault, source)
  local resolved, err = path_policy.resolve(vault, source, { allow_absolute = true })
  if not resolved then
    return nil, err
  end
  if not resolved.logical:match("%.md$") or vim.fn.filereadable(resolved.path) ~= 1 then
    return nil, coded_error(E.NOT_A_NOTE_FILE, "Failed to move: selected path is not a readable Markdown note")
  end
  return resolved
end

local function source_input(opts)
  if opts.source then
    return opts.source
  end
  local entry = require("miniobsidian.explorer").current_entry()
  if entry then
    if entry.type ~= "file" then
      return nil, coded_error(E.NOT_A_NOTE_FILE, "Failed to move: file tree selection is not a note file")
    end
    return entry.path
  end
  local current = vim.api.nvim_buf_get_name(0)
  if current == "" then
    return nil, coded_error(E.NO_ACTIONABLE_NOTE, "Failed to move: no actionable note in current buffer or file tree")
  end
  return current
end

local function snacks_input_key(lhs, action)
  local spec = { lhs, action }
  spec.mode = "i"
  spec.expr = true
  return spec
end

local function move_prompt(on_confirm)
  local opts = {
    prompt = "Move to Vault-relative note path (end directories with /): ",
    completion = "customlist,v:lua.require'miniobsidian.note_move'.complete_directories",
  }

  -- `win.keys` 是 Snacks 输入框特有的选项。原生 vim.ui.input 会把 opts 转成
  -- VimL，遇到 Snacks 这种数组与字典混用的键 spec 时会报 E5100。
  if package.loaded.snacks ~= nil then
    local ok, snacks_input = pcall(require, "snacks.input")
    if ok and type(snacks_input.input) == "function" then
      opts.win = {
        keys = {
          i_up = snacks_input_key("<up>", { "cmp_select_prev", "cmp" }),
          i_down = snacks_input_key("<down>", { "cmp_select_next", "cmp" }),
          i_h = snacks_input_key("h", function()
            return vim.fn.pumvisible() == 1 and "<c-p>" or "h"
          end),
          i_j = snacks_input_key("j", function()
            return vim.fn.pumvisible() == 1 and "<c-n>" or "j"
          end),
          i_k = snacks_input_key("k", function()
            return vim.fn.pumvisible() == 1 and "<c-p>" or "k"
          end),
        },
      }
      snacks_input.input(opts, on_confirm)
      return
    end
  end

  vim.ui.input(opts, on_confirm)
end

---Complete safe Vault-relative directories for note moves.
---@param arg_lead? string
---@param cmd_line? string
---@param cursor_pos? integer
---@return string[]
function M.complete_directories(arg_lead, cmd_line, cursor_pos)
  local core = require("miniobsidian")
  local vault = core.config.vault_path
  if vim.fn.isdirectory(vault) == 0 then
    return {}
  end

  local lead = arg_lead or ""
  if cmd_line and cursor_pos then
    local before_cursor = cmd_line:sub(1, cursor_pos)
    lead = before_cursor:match("^%s*ObsidianMove%s+(.*)$") or lead
  end
  lead = lead:match("^%s*(.-)%s*$"):gsub("\\", "/"):lower()

  local seen = {}
  local candidates = {}
  for _, absolute in ipairs(vim.fn.globpath(vault, "**/", false, true)) do
    if vim.fn.isdirectory(absolute) == 1 then
      local resolved = path_policy.resolve(vault, absolute, { allow_absolute = true })
      if resolved and resolved.logical ~= "" then
        local candidate = resolved.logical .. "/"
        if not seen[candidate] and candidate:lower():sub(1, #lead) == lead then
          seen[candidate] = true
          candidates[#candidates + 1] = candidate
        end
      end
    end
  end
  table.sort(candidates)
  return candidates
end

local function resolve_target(vault, source, destination, destination_is_file)
  if type(destination) ~= "string" then
    return nil, coded_error(E.TARGET_NOT_STRING, "Failed to move: target path must be a string")
  end
  destination = destination:match("^%s*(.-)%s*$")
  local directory_hint = destination:match("[/\\]$") ~= nil
  local possible_directory = path_policy.resolve(vault, destination, { allow_empty = true })
  local existing_directory = possible_directory and vim.fn.isdirectory(possible_directory.path) == 1
  if destination_is_file == nil then
    destination_is_file = not directory_hint and not existing_directory
  end

  local logical
  if destination_is_file then
    logical = destination:lower():match("%.md$") and destination or (destination .. ".md")
  else
    logical = path_policy.join(destination, assert(basename(source.logical)))
  end
  local resolved, err = path_policy.resolve(vault, logical)
  if not resolved then
    return nil, err
  end
  if not resolved.logical:match("%.md$") then
    return nil, coded_error(E.TARGET_NOT_MD, "Failed to move: target file must use the .md extension")
  end
  if path_policy.normalize(resolved.path) == path_policy.normalize(source.path) then
    return nil, coded_error(E.ALREADY_AT_TARGET, "Failed to move: note is already at the target path")
  end
  if resolved.exists and not same_path(resolved.path, source.path) then
    return nil, coded_error(E.TARGET_EXISTS, "Failed to move: target note already exists: " .. resolved.logical)
  end
  return resolved
end

local function note_basename(id)
  return id:match("([^/]+)$") or id
end

local function short_target_is_unique(notes, vault, source, new_id)
  local wanted = note_basename(new_id):lower()
  local matches = 0
  for _, note_path in ipairs(notes) do
    local id
    if same_path(note_path, source.path) then
      id = new_id
    else
      local resolved = path_policy.resolve(vault, note_path, { allow_absolute = true })
      id = resolved and strip_md(resolved.logical) or nil
    end
    if id and note_basename(id):lower() == wanted then
      matches = matches + 1
      if matches > 1 then
        return false
      end
    end
  end
  return matches == 1
end

local function rewrite_link(inner, notes, vault, old_id, new_id, short_unique)
  local parsed = wikilink.parse(inner)
  if not parsed then
    return nil
  end
  local target = wikilink.resolve(parsed, notes, vault)
  if not target then
    return nil
  end
  -- A new basename can also make a previously unique link to another note ambiguous.
  -- Preserve its pre-move identity by qualifying it before publishing the new name.
  if target.id ~= old_id then
    if parsed.target:find("/", 1, true) or note_basename(target.id):lower() ~= note_basename(new_id):lower() then
      return nil
    end
    new_id = target.id
    short_unique = false
  end

  local suffix_at = inner:find("[#|]")
  local suffix = suffix_at and inner:sub(suffix_at) or ""
  local original_target = suffix_at and inner:sub(1, suffix_at - 1) or inner
  local extension = original_target:lower():match("%.md%s*$") and ".md" or ""
  local qualified = parsed.target:find("/", 1, true) ~= nil
  local replacement_target = (qualified or not short_unique) and new_id or note_basename(new_id)
  local replacement = "[[" .. replacement_target .. extension .. suffix .. "]]"
  if replacement == "[[" .. inner .. "]]" then
    return nil
  end
  return replacement
end

local function rewrite_wikilinks(content, notes, vault, old_id, new_id, short_unique)
  return markdown.transform(content, function(line, visible)
    return markdown.wikilinks(line, visible, function(inner)
      return rewrite_link(inner, notes, vault, old_id, new_id, short_unique)
    end)
  end)
end

local function replace_yaml_title(line, old_title, new_title)
  for _, quote in ipairs({ '"', "'" }) do
    local prefix, value, trailing = line:match("^(%s*title%s*:%s*)" .. quote .. "(.*)" .. quote .. "(%s*)$")
    local decoded = value
    if prefix then
      if quote == "'" then
        decoded = value:gsub("''", "'")
      else
        local ok, parsed = pcall(vim.json.decode, '"' .. value .. '"')
        decoded = ok and parsed or value
      end
    end
    if prefix and decoded == old_title then
      local encoded = quote == "'" and ("'" .. new_title:gsub("'", "''") .. "'")
        or require("miniobsidian").yaml_quote(new_title)
      return prefix .. encoded .. trailing, true
    end
  end

  local prefix, value, trailing = line:match("^(%s*title%s*:%s*)(%S.-)(%s*)$")
  if prefix and value == old_title then
    return prefix .. require("miniobsidian").yaml_quote(new_title) .. trailing, true
  end
  return line, false
end

local function replace_h1(line, old_title, new_title)
  local prefix, body = line:match("^(%s*#%s+)(.*)$")
  if not prefix then
    return line, false, false
  end

  local heading, closing = body:match("^(.-)(%s+#+%s*)$")
  heading = heading or body
  closing = closing or ""
  local leading, value, trailing = heading:match("^(%s*)(.-)(%s*)$")
  if value == old_title then
    return prefix .. leading .. new_title .. trailing .. closing, true, true
  end
  return line, false, true
end

local function rewrite_note_identity(content, old_title, new_title)
  if old_title == new_title then
    return content, 0
  end

  local in_frontmatter = false
  local first_h1_seen = false
  return markdown.transform(content, function(line, visible, line_number)
    local changed = false
    if line_number == 1 and line:match("^%s*%-%-%-%s*$") then
      in_frontmatter = true
    elseif in_frontmatter and (line:match("^%s*%-%-%-%s*$") or line:match("^%s*%.%.%.%s*$")) then
      in_frontmatter = false
    elseif in_frontmatter then
      line, changed = replace_yaml_title(line, old_title, new_title)
    elseif not first_h1_seen and visible:match("^%s*#%s+") then
      local is_h1
      line, changed, is_h1 = replace_h1(line, old_title, new_title)
      first_h1_seen = is_h1
    end
    return line, changed and 1 or 0
  end)
end

local function build_updates(notes, vault, source, target)
  local updates = {}
  local old_id = strip_md(source.logical)
  local new_id = strip_md(target.logical)
  local old_title = strip_md(assert(basename(source.logical)))
  local new_title = strip_md(assert(basename(target.logical)))
  local total_links = 0
  local total_identity_fields = 0

  -- 优先使用 scanner 解析出的 Note ID，这样内部符号链接别名与 wikilink.resolve()
  -- 使用的身份保持一致。解析失败时回退到 source 已经校验过的 logical path。
  for _, note_path in ipairs(notes) do
    if same_path(note_path, source.path) then
      local scanned = path_policy.resolve(vault, note_path, { allow_absolute = true })
      if scanned then
        old_id = strip_md(scanned.logical)
      end
      break
    end
  end

  local short_unique = short_target_is_unique(notes, vault, source, new_id)

  for _, note_path in ipairs(notes) do
    local content, read_err = fs.read(note_path)
    if not content then
      return nil, coded_error(E.READ_NOTE_FAILED, "Failed to read note " .. note_path .. ": " .. tostring(read_err))
    end
    local rewritten, link_count = rewrite_wikilinks(content, notes, vault, old_id, new_id, short_unique)
    local identity_count = 0
    if same_path(note_path, source.path) then
      local relative_links
      rewritten, relative_links = require("miniobsidian.markdown_link").rebase(
        rewritten,
        dirname(source.path),
        dirname(target.path),
        vault,
        { old_path = source.real_path, new_path = target.path }
      )
      link_count = link_count + relative_links
      rewritten, identity_count = rewrite_note_identity(rewritten, old_title, new_title)
    end
    if rewritten ~= content then
      updates[#updates + 1] = {
        old_path = note_path,
        path = same_path(note_path, source.path) and target.path or note_path,
        before = content,
        after = rewritten,
      }
      total_links = total_links + link_count
      total_identity_fields = total_identity_fields + identity_count
    end
  end
  return updates, total_links, total_identity_fields
end

local function rollback(source, target, written)
  local failures = {}
  for index = #written, 1, -1 do
    local update = written[index]
    local ok, err = fs.write_atomic(update.path, update.before)
    if not ok then
      failures[#failures + 1] = tostring(err)
    end
  end
  local moved_back, move_err = uv.fs_rename(target.path, source.path)
  if not moved_back then
    failures[#failures + 1] = tostring(move_err)
  end
  return #failures == 0, table.concat(failures, "; ")
end

local function refresh_buffers(source_buffer, source, target, updates)
  if source_buffer and vim.api.nvim_buf_is_valid(source_buffer) then
    local ok, err = pcall(vim.api.nvim_buf_set_name, source_buffer, target.path)
    if not ok then
      require("miniobsidian").notify("Failed to update buffer path after move: " .. tostring(err), vim.log.levels.WARN)
    end
  end

  local changed = {}
  local changed_paths = {}
  local source_changed = false
  for _, update in ipairs(updates) do
    changed[path_policy.normalize(update.old_path)] = true
    changed_paths[#changed_paths + 1] = update.old_path
    source_changed = source_changed or update.path == target.path
  end
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buffer) then
      local name = vim.api.nvim_buf_get_name(buffer)
      local previous_name = buffer == source_buffer and source.path or name
      local was_changed = (buffer == source_buffer and source_changed)
        or changed[path_policy.normalize(previous_name)] == true
      if not was_changed then
        for _, changed_path in ipairs(changed_paths) do
          if same_path(previous_name, changed_path) then
            was_changed = true
            break
          end
        end
      end
      if was_changed then
        pcall(vim.api.nvim_buf_call, buffer, function()
          vim.cmd("silent noautocmd edit!")
        end)
      end
    end
  end
end

local function notify_lsp_rename(source, target, updates)
  if not vim.lsp then
    return
  end
  local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
  if not get_clients then
    return
  end

  local params = {
    files = {
      {
        oldUri = vim.uri_from_fname(source.path),
        newUri = vim.uri_from_fname(target.path),
      },
    },
  }
  local watched_changes = {
    { uri = vim.uri_from_fname(source.path), type = 3 },
    { uri = vim.uri_from_fname(target.path), type = 1 },
  }
  local watched_uris = {
    [watched_changes[1].uri] = true,
    [watched_changes[2].uri] = true,
  }
  for _, update in ipairs(updates) do
    local uri = vim.uri_from_fname(update.path)
    if not watched_uris[uri] then
      watched_changes[#watched_changes + 1] = { uri = uri, type = 2 }
      watched_uris[uri] = true
    end
  end

  local function supports(client, method)
    if type(client.supports_method) ~= "function" then
      return false
    end
    local ok, result = pcall(client.supports_method, client, method)
    return ok and result == true
  end

  for _, client in ipairs(get_clients()) do
    if supports(client, "workspace/didRenameFiles") and type(client.notify) == "function" then
      pcall(client.notify, client, "workspace/didRenameFiles", params)
    end
    if supports(client, "workspace/didChangeWatchedFiles") and type(client.notify) == "function" then
      pcall(client.notify, client, "workspace/didChangeWatchedFiles", { changes = watched_changes })
    end
  end
end

local function perform(destination, opts)
  opts = opts or {}
  local core = require("miniobsidian")
  local operation = opts.operation == "rename" and "rename" or "move"
  local action = operation == "rename" and "rename" or "move"
  local vault = core.config.vault_path
  local selected, selection_err = source_input(opts)
  if not selected then
    return nil, selection_err
  end
  local source, source_err = resolve_source(vault, selected)
  if not source then
    return nil, source_err
  end

  local source_buffer, save_err = save_source_buffer(source.path)
  if save_err then
    return nil, save_err
  end
  local modified = modified_vault_buffer(vault, source.path)
  if modified then
    return nil,
      coded_error(E.UNSAVED_PEERS, "Failed to move: unsaved Vault notes would break reference updates: " .. modified)
  end

  local target, target_err = resolve_target(vault, source, destination, opts.destination_is_file)
  if not target then
    return nil, target_err
  end
  local target_buffer = vim.fn.bufnr(target.path)
  local released, release_err = release_stale_target_buffer(target_buffer, source_buffer)
  if not released then
    return nil, release_err
  end

  local notes = core.get_all_notes(true)
  local updates, total_links, total_identity_fields = build_updates(notes, vault, source, target)
  if not updates then
    return nil, total_links
  end

  local parent = dirname(target.path)
  if vim.fn.mkdir(parent, "p") == 0 and vim.fn.isdirectory(parent) == 0 then
    return nil, coded_error(E.CREATE_DIRECTORY_FAILED, "Failed to create target directory: " .. parent)
  end
  local moved, move_err = uv.fs_rename(source.path, target.path)
  if not moved then
    local code = operation == "rename" and E.RENAME_FAILED or E.MOVE_FAILED
    return nil, coded_error(code, "Failed to " .. action .. " note: " .. tostring(move_err))
  end

  local written = {}
  for _, update in ipairs(updates) do
    local ok, write_err = fs.write_atomic(update.path, update.after)
    if not ok then
      local rollback_ok, rollback_err = rollback(source, target, written)
      local message = coded_error(
        E.UPDATE_REFERENCES_FAILED,
        "Failed to update references; " .. action .. " rolled back: " .. tostring(write_err)
      )
      if not rollback_ok then
        message = message .. "; rollback incomplete: " .. rollback_err
      end
      return nil, message
    end
    written[#written + 1] = update
  end

  refresh_buffers(source_buffer, source, target, updates)
  notify_lsp_rename(source, target, updates)
  core.invalidate_cache()
  local result = {
    operation = operation,
    old_path = source.path,
    new_path = target.path,
    updated_files = #updates,
    updated_links = total_links,
    updated_identity_fields = total_identity_fields,
  }
  local event = operation == "rename" and "MiniObsidianNoteRenamed" or "MiniObsidianNoteMoved"
  vim.api.nvim_exec_autocmds("User", { pattern = event, data = result })
  return result
end

---Move the current note to a Vault-relative note path.
---A trailing slash or an existing directory preserves the current filename.
---@param destination? string
---@param opts? {source?: string, destination_is_file?: boolean, notify?: boolean}
---@return table|nil result
---@return string|nil error
function M.move(destination, opts)
  opts = opts or {}
  local core = require("miniobsidian")
  if destination == nil then
    local selected, selection_err = source_input(opts)
    if not selected then
      if opts.notify ~= false then
        core.notify(selection_err, vim.log.levels.ERROR)
      end
      return nil, selection_err
    end
    local prompt_opts = vim.tbl_extend("force", opts, { source = selected })
    move_prompt(function(choice)
      if choice == nil or choice == "" then
        return
      end
      vim.schedule(function()
        M.move(choice, prompt_opts)
      end)
    end)
    return nil
  end

  local result, err = perform(destination, opts)
  if not result then
    if opts.notify ~= false then
      core.notify(err, vim.log.levels.ERROR)
    end
    return nil, err
  end
  if opts.notify ~= false then
    core.notify(
      string.format(
        "Note moved; updated %d references across %d files and synced %d titles",
        result.updated_links,
        result.updated_files,
        result.updated_identity_fields
      )
    )
  end
  return result
end

local function rename_target(name, opts)
  if type(name) ~= "string" then
    return nil, coded_error(E.RENAME_NOT_STRING, "Failed to rename: new filename must be a string")
  end
  name = name:match("^%s*(.-)%s*$")
  if name == "" then
    return nil, coded_error(E.RENAME_EMPTY, "Failed to rename: new filename cannot be empty")
  end
  if name:find("/", 1, true) or name:find("\\", 1, true) then
    return nil,
      coded_error(
        E.RENAME_ONLY_FILENAME,
        "Failed to rename: rename accepts only a filename; use ObsidianMove for directories"
      )
  end

  local core = require("miniobsidian")
  local selected, selection_err = source_input(opts)
  if not selected then
    return nil, selection_err
  end
  local source, source_err = resolve_source(core.config.vault_path, selected)
  if not source then
    return nil, source_err
  end
  local filename = name:lower():match("%.md$") and name or (name .. ".md")
  return path_policy.join(dirname(source.logical), filename)
end

---Rename the current note in place and update resolved Wikilinks.
---@param name? string New filename; .md is optional
---@param opts? {source?: string, notify?: boolean}
---@return table|nil result
---@return string|nil error
function M.rename(name, opts)
  opts = opts or {}
  local core = require("miniobsidian")
  if name == nil then
    local selected, selection_err = source_input(opts)
    if not selected then
      if opts.notify ~= false then
        core.notify(selection_err, vim.log.levels.ERROR)
      end
      return nil, selection_err
    end
    local source = resolve_source(core.config.vault_path, selected)
    local default = source and strip_md(assert(basename(source.logical))) or ""
    local prompt_opts = vim.tbl_extend("force", opts, { source = selected })
    vim.ui.input({ prompt = "Rename note: ", default = default }, function(choice)
      if choice == nil or choice == "" then
        return
      end
      vim.schedule(function()
        M.rename(choice, prompt_opts)
      end)
    end)
    return nil
  end

  local target, target_err = rename_target(name, opts)
  if not target then
    if opts.notify ~= false then
      core.notify(target_err, vim.log.levels.ERROR)
    end
    return nil, target_err
  end
  local perform_opts = vim.tbl_extend("force", opts, { destination_is_file = true, operation = "rename" })
  local result, err = perform(target, perform_opts)
  if not result then
    if opts.notify ~= false then
      core.notify(err, vim.log.levels.ERROR)
    end
    return nil, err
  end
  if opts.notify ~= false then
    core.notify(
      string.format(
        "Note renamed; updated %d references across %d files and synced %d titles",
        result.updated_links,
        result.updated_files,
        result.updated_identity_fields
      )
    )
  end
  return result
end

return M
