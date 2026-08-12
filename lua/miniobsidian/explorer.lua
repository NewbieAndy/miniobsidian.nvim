local M = {}

---返回当前文件浏览器光标对应的文件或目录。
---支持顺序：snacks explorer、neo-tree、nvim-tree、oil.nvim、netrw。
---@return {path: string, type: "file"|"directory"}|nil
function M.current_entry()
  local current_win = vim.api.nvim_get_current_win()
  local ft = vim.bo.filetype

  local ok_snacks, snacks = pcall(require, "snacks")
  if ok_snacks and snacks.picker then
    local ok_pickers, pickers = pcall(snacks.picker.get, { source = "explorer" })
    if ok_pickers and pickers then
      for _, picker in ipairs(pickers) do
        local list_win = picker.list and picker.list.win and picker.list.win.win
        if list_win == current_win then
          local ok_items, items = pcall(function()
            return picker:selected({ fallback = true })
          end)
          local path = ok_items and items and items[1] and items[1].file
          if path and path ~= "" then
            local clean = path:gsub("/+$", "")
            return { path = clean, type = vim.fn.isdirectory(path) == 1 and "directory" or "file" }
          end
        end
      end
    end
  end

  if ft == "neo-tree" then
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok then
      local state = manager.get_state("filesystem")
      local node = state and state.tree and state.tree:get_node()
      if node and node.path then
        return { path = node.path, type = node.type == "directory" and "directory" or "file" }
      end
    end
  end

  if ft == "NvimTree" then
    local ok, api = pcall(require, "nvim-tree.api")
    if ok then
      local ok_node, node = pcall(api.tree.get_node_under_cursor)
      if ok_node and node and node.absolute_path then
        return { path = node.absolute_path, type = node.type == "directory" and "directory" or "file" }
      end
    end
  end

  if ft == "oil" then
    local ok, oil = pcall(require, "oil")
    if ok then
      local ok_dir, dir = pcall(oil.get_current_dir)
      if ok_dir and dir then
        local ok_entry, entry = pcall(oil.get_cursor_entry)
        if ok_entry and entry and entry.name then
          local path = (dir:gsub("/+$", "") .. "/" .. entry.name):gsub("/+$", "")
          return { path = path, type = entry.type == "directory" and "directory" or "file" }
        end
        return { path = dir:gsub("/+$", ""), type = "directory" }
      end
    end
  end

  if ft == "netrw" then
    local curdir = vim.b.netrw_curdir
    if curdir and curdir ~= "" then
      local name = vim.fn.expand("<cfile>")
      if name and name ~= "" and name ~= "." and name ~= ".." then
        local full = curdir .. "/" .. name
        if vim.fn.isdirectory(full) == 1 then
          return { path = full, type = "directory" }
        end
        return { path = full, type = "file" }
      end
      return { path = curdir, type = "directory" }
    end
  end

  return nil
end

---返回当前文件浏览器光标对应的目录。
---@return string|nil
function M.current_dir()
  local entry = M.current_entry()
  if not entry then
    return nil
  end
  return entry.type == "directory" and entry.path or vim.fn.fnamemodify(entry.path, ":h")
end

return M
