-- Local Markdown destinations: encoding for attachments and rebasing during moves.
local M = {}
local path_policy = require("miniobsidian.path")
local markdown = require("miniobsidian.markdown")

function M.encode_path(path)
  return (path:gsub("[^A-Za-z0-9._~/-]", function(byte)
    return string.format("%%%02X", byte:byte())
  end))
end

function M.escape_label(label)
  return (label:gsub("([\\%[%]])", "\\%1"))
end

local function skip_space(line, index)
  while line:sub(index, index):match("%s") do
    index = index + 1
  end
  return index
end

-- Return byte boundaries of a destination, excluding optional angle brackets.
local function destination(line, index)
  index = skip_space(line, index)
  local first = index
  if line:sub(index, index) == "<" then
    first = index + 1
    index = first
    while index <= #line do
      local char = line:sub(index, index)
      if char == "\\" then
        index = index + 2
      elseif char == ">" then
        return first, index - 1, index + 1
      else
        index = index + 1
      end
    end
    return nil
  end
  local depth = 0
  while index <= #line do
    local char = line:sub(index, index)
    if char == "\\" then
      index = index + 2
    elseif char == "(" then
      depth = depth + 1
      index = index + 1
    elseif char == ")" then
      if depth == 0 then
        break
      end
      depth = depth - 1
      index = index + 1
    elseif char:match("%s") then
      break
    else
      index = index + 1
    end
  end
  if depth ~= 0 then
    return nil
  end
  return first, index - 1, index
end

local function after_title(line, index)
  index = skip_space(line, index)
  local quote = line:sub(index, index)
  local closing = quote == "(" and ")" or quote
  if quote == '"' or quote == "'" or quote == "(" then
    index = index + 1
    while index <= #line do
      if line:sub(index, index) == "\\" then
        index = index + 2
      elseif line:sub(index, index) == closing then
        return skip_space(line, index + 1)
      else
        index = index + 1
      end
    end
    return #line + 1
  end
  return index
end

local function rebase(raw, from_dir, to_dir, vault, moved_note)
  if raw == "" or raw:match("^[#?/]") or raw:match("^%a[%w+.-]*:") then
    return nil
  end
  local path, suffix = raw:match("^([^#?]*)(.*)$")
  path = path:gsub("\\(%p)", "%1"):gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  if path == "" or path:find("%z") then
    return nil
  end
  local absolute = vim.fn.simplify(path_policy.join(from_dir, path))
  local resolved = path_policy.resolve(vault, absolute, { allow_absolute = true })
  if not resolved then
    return nil
  end
  local target = resolved.path
  if moved_note and resolved.real_path == moved_note.old_path then
    target = moved_note.new_path
  end
  if from_dir == to_dir and target == resolved.path then
    return nil
  end
  local relative = path_policy.relative(to_dir, target)
  return relative and (M.encode_path(relative) .. suffix) or nil
end

local function rewrite_line(line, visible, from_dir, to_dir, vault, moved_note)
  local edits = {}
  local function add(first, last)
    local raw = line:sub(first, last)
    local replacement = rebase(raw, from_dir, to_dir, vault, moved_note)
    if replacement and replacement ~= raw then
      edits[#edits + 1] = { first, last, replacement }
    end
  end
  -- Same-line reference definitions share the same destination syntax as inline links.
  local label, stop = visible:match("^ ? ? ?%[([^%]]+)%]:%s*()")
  if label and label:sub(1, 1) ~= "^" then
    local first, last, next_index = destination(line, stop)
    if first and after_title(line, next_index) > #line then
      add(first, last)
    end
  else
    local index = 1
    while index <= #line do
      local open = visible:find("[", index, true)
      if not open then
        break
      end
      if visible:sub(open, open + 1) == "[[" then
        local close = visible:find("]]", open + 2, true)
        index = close and close + 2 or #line + 1
      else
        local depth, cursor = 1, open + 1
        while cursor <= #line and depth > 0 do
          local char = line:sub(cursor, cursor)
          if char == "\\" then
            cursor = cursor + 2
          else
            if char == "[" then
              depth = depth + 1
            end
            if char == "]" then
              depth = depth - 1
            end
            cursor = cursor + 1
          end
        end
        index = cursor
        if depth == 0 and visible:sub(cursor, cursor) == "(" then
          local first, last, next_index = destination(line, cursor + 1)
          if first then
            local close = after_title(line, next_index)
            if line:sub(close, close) == ")" then
              add(first, last)
              index = close + 1
            end
          end
        end
      end
    end
  end
  for index = #edits, 1, -1 do
    local edit = edits[index]
    line = line:sub(1, edit[1] - 1) .. edit[3] .. line:sub(edit[2] + 1)
  end
  return line, #edits
end

---Rebase Vault-local relative destinations in a moved note; leave URLs and anchors alone.
function M.rebase(content, from_dir, to_dir, vault, moved_note)
  local from = path_policy.resolve(vault, from_dir, { allow_absolute = true, allow_empty = true })
  local to = path_policy.resolve(vault, to_dir, { allow_absolute = true, allow_empty = true })
  if not from or not to then
    return content, 0
  end
  from_dir, to_dir = from.path, to.path
  if from_dir == to_dir and not moved_note then
    return content, 0
  end
  return markdown.transform(content, function(line, visible)
    return rewrite_line(line, visible, from_dir, to_dir, vault, moved_note)
  end)
end

return M
