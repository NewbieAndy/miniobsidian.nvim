local M = {}

local uv = vim.uv or vim.loop

local function is_exists_error(err)
  return type(err) == "string" and err:match("^EEXIST") ~= nil
end

---Read a complete file as bytes.
---@param path string
---@return string|nil content
---@return string|nil error
function M.read(path)
  local file, open_err = io.open(path, "rb")
  if not file then
    return nil, tostring(open_err)
  end
  local ok, content = pcall(file.read, file, "*a")
  local closed, close_err = file:close()
  if not ok then
    return nil, tostring(content)
  end
  if not closed then
    return nil, tostring(close_err or "close failed")
  end
  return content, nil
end

---Read a text file into lines using Neovim's newline semantics.
---@param path string
---@return string[]|nil lines
---@return string|nil error
function M.read_lines(path)
  local content, err = M.read(path)
  if not content then
    return nil, err
  end
  if content == "" then
    return {}, nil
  end
  local lines = vim.split(content, "\n", { plain = true })
  if content:sub(-1) == "\n" then
    table.remove(lines, #lines)
  end
  return lines, nil
end

---Best-effort removal for plugin-owned temporary files.
---@param path string
---@return boolean
function M.unlink(path)
  if not uv.fs_stat(path) then
    return true
  end
  return uv.fs_unlink(path) ~= nil
end

---Create a file without replacing an existing path.
---@param path string
---@param content string
---@param mode? integer
---@return boolean|nil created false means the target already exists
---@return string|nil error
function M.create_exclusive(path, content, mode)
  local fd, open_err = uv.fs_open(path, "wx", mode or 420)
  if not fd then
    if is_exists_error(open_err) then
      return false, nil
    end
    return nil, tostring(open_err)
  end

  local offset = 0
  local failure
  while offset < #content do
    local written, write_err = uv.fs_write(fd, content:sub(offset + 1), offset)
    if not written or written <= 0 then
      failure = tostring(write_err or "write returned no progress")
      break
    end
    offset = offset + written
  end
  if not failure then
    local synced, sync_err = uv.fs_fsync(fd)
    if not synced then
      failure = tostring(sync_err or "fsync failed")
    end
  end

  local closed, close_err = uv.fs_close(fd)
  if not closed and not failure then
    failure = tostring(close_err or "close failed")
  end
  if failure then
    uv.fs_unlink(path)
    return nil, failure
  end
  return true, nil
end

---Publish an existing file at a new path without replacing an existing target.
---The source and target should be on the same filesystem. The caller owns source cleanup.
---@param source string
---@param target string
---@return boolean|nil linked false means the target already exists
---@return string|nil error
function M.link_exclusive(source, target)
  local linked, link_err = uv.fs_link(source, target)
  if linked then
    return true, nil
  end
  if is_exists_error(link_err) then
    return false, nil
  end
  return nil, tostring(link_err)
end

return M
