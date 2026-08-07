local M = {}

local uv = vim.uv or vim.loop

local function is_exists_error(err)
  return type(err) == "string" and err:match("^EEXIST") ~= nil
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

return M
