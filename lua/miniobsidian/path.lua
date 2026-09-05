local M = {}

local uv = vim.uv or vim.loop
local is_windows = uv.os_uname().sysname:lower():find("windows", 1, true) ~= nil
local windows_devices = {
  CON = true,
  PRN = true,
  AUX = true,
  NUL = true,
}

for i = 1, 9 do
  windows_devices["COM" .. i] = true
  windows_devices["LPT" .. i] = true
end

local function fail(message)
  return nil, "PATH_OUTSIDE_VAULT: " .. message
end

local function comparison_value(value)
  value = M.normalize(value)
  return is_windows and value:lower() or value
end

local function is_absolute(value)
  return value:sub(1, 1) == "/" or value:match("^%a:/") ~= nil or value:sub(1, 2) == "//"
end

local function parent(path)
  local normalized = M.normalize(path)
  if normalized == "/" or normalized:match("^%a:/$") then
    return normalized
  end
  local result = normalized:match("^(.*)/[^/]+$")
  if not result or result == "" then
    return normalized:sub(1, 1) == "/" and "/" or "."
  end
  return result
end

local function basename(path)
  return M.normalize(path):match("([^/]+)$")
end

local function validate_segment(segment)
  if segment == "" or segment == "." or segment == ".." then
    return fail("Path contains empty, current, or parent directory segment")
  end
  if segment:sub(1, 1) == "." then
    return fail("Content path cannot contain hidden directories")
  end
  if segment:find(":", 1, true) then
    return fail("Path cannot contain Windows ADS separator")
  end
  if segment:match("[%. ]$") then
    return fail("Path segment cannot end with a dot or space")
  end

  local device = segment:match("^([^%.]+)")
  if device and windows_devices[device:upper()] then
    return fail("Path contains a Windows reserved device name")
  end
  return true
end

function M.normalize(path)
  if type(path) ~= "string" then
    return ""
  end
  local normalized = path:gsub("\\", "/"):gsub("/+", "/")
  if #normalized > 1 and not normalized:match("^%a:/$") then
    normalized = normalized:gsub("/+$", "")
  end
  return normalized
end

function M.join(...)
  local parts = { ... }
  local result = ""
  for _, part in ipairs(parts) do
    if part ~= nil and part ~= "" then
      if result == "" then
        result = tostring(part)
      else
        result = result:gsub("[/\\]+$", "") .. "/" .. tostring(part):gsub("^[/\\]+", "")
      end
    end
  end
  return M.normalize(result)
end

function M.relative(from, to)
  from = M.normalize(from)
  to = M.normalize(to)
  if not is_absolute(from) or not is_absolute(to) then
    return nil
  end

  local from_drive = from:match("^(%a:)")
  local to_drive = to:match("^(%a:)")
  if (from_drive or to_drive) and comparison_value(from_drive or "") ~= comparison_value(to_drive or "") then
    return nil
  end

  local from_parts = vim.split(from:gsub("^%a:/", ""):gsub("^/", ""), "/", { plain = true })
  local to_parts = vim.split(to:gsub("^%a:/", ""):gsub("^/", ""), "/", { plain = true })
  local common = 0
  for i = 1, math.min(#from_parts, #to_parts) do
    if comparison_value(from_parts[i]) ~= comparison_value(to_parts[i]) then
      break
    end
    common = i
  end

  local result = {}
  for _ = common + 1, #from_parts do
    result[#result + 1] = ".."
  end
  for i = common + 1, #to_parts do
    result[#result + 1] = to_parts[i]
  end
  return table.concat(result, "/")
end

function M.realpath(path)
  path = M.normalize(path)
  local resolved = uv.fs_realpath(path)
  return resolved and M.normalize(resolved) or nil
end

local function resolve_nearest(path)
  local current = M.normalize(path)
  local tail = {}

  while not uv.fs_stat(current) do
    local name = basename(current)
    local next_parent = parent(current)
    if not name or next_parent == current then
      return nil
    end
    table.insert(tail, 1, name)
    current = next_parent
  end

  local resolved = M.realpath(current)
  if not resolved then
    return nil
  end
  for _, segment in ipairs(tail) do
    resolved = M.join(resolved, segment)
  end
  return resolved
end

function M.is_within_vault(vault, candidate)
  if type(vault) ~= "string" or vault == "" or type(candidate) ~= "string" or candidate == "" then
    return false
  end
  local root = M.realpath(vault)
  local target = resolve_nearest(candidate)
  if not root or not target then
    return false
  end
  local rel = M.relative(root, target)
  return rel ~= nil and rel ~= ".." and rel:sub(1, 3) ~= "../"
end

function M.validate_logical(logical, opts)
  opts = opts or {}
  if type(logical) ~= "string" or logical == "" then
    if opts.allow_empty then
      return ""
    end
    return fail("Path cannot be empty")
  end
  if logical:find("%z") then
    return fail("Path cannot contain NUL")
  end

  local normalized = logical:gsub("\\", "/")
  if normalized:sub(1, 1) == "~" or is_absolute(normalized) or normalized:match("^%a:") then
    return fail("Content path must be Vault-relative")
  end

  for _, segment in ipairs(vim.split(normalized, "/", { plain = true })) do
    local ok, err = validate_segment(segment)
    if not ok then
      return nil, err
    end
  end
  return normalized
end

---@param vault string
---@param input string Vault 相对路径；allow_absolute 时也可传绝对路径
---@param opts? {allow_absolute?: boolean, allow_empty?: boolean}
---@return {path: string, logical: string, real_path: string, exists: boolean}|nil
---@return string|nil
function M.resolve(vault, input, opts)
  opts = opts or {}
  local root = M.realpath(vault)
  if not root then
    return fail("Vault root directory does not exist or cannot be resolved")
  end

  local candidate
  local logical
  local normalized_input = M.normalize(input)
  if opts.allow_absolute and is_absolute(normalized_input) then
    candidate = resolve_nearest(normalized_input)
    if not candidate then
      return fail("Absolute path cannot be resolved")
    end
    logical = M.relative(root, candidate)
    if not logical or logical == ".." or logical:sub(1, 3) == "../" then
      return fail("Absolute path is outside the current Vault")
    end
    local valid, err = M.validate_logical(logical, { allow_empty = opts.allow_empty })
    if not valid then
      return nil, err
    end
    logical = valid
  else
    local valid, err = M.validate_logical(input, { allow_empty = opts.allow_empty })
    if valid == nil then
      return nil, err
    end
    logical = valid
    candidate = logical == "" and root or M.join(root, logical)
  end

  local resolved = resolve_nearest(candidate)
  if not resolved or not M.is_within_vault(root, candidate) then
    return fail("Path escapes the Vault after symlink resolution")
  end
  return {
    path = candidate,
    logical = logical,
    real_path = resolved,
    exists = uv.fs_stat(candidate) ~= nil,
  }
end

return M
