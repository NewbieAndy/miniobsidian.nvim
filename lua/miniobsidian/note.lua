---Public note facade. Creation, explorer detection, and picker integration live in
---smaller modules while these established API names remain compatible.
local M = {}
local path_policy = require("miniobsidian.path")

function M.new_note(...)
  return require("miniobsidian.note_create").new_note(...)
end

function M.new_note_in_dir(...)
  return require("miniobsidian.note_create").new_note_in_dir(...)
end

function M.new_note_here(...)
  return require("miniobsidian.note_create").new_note_here(...)
end

function M._create_note(...)
  return require("miniobsidian.note_create").create(...)
end

function M.quick_switch(...)
  return require("miniobsidian.note_picker").quick_switch(...)
end

function M.search(...)
  return require("miniobsidian.note_picker").search(...)
end

---@param input string|table Wikilink target or parsed result
function M.follow_or_create(input)
  local core = require("miniobsidian")
  local notes = core.get_all_notes()
  local wikilink = require("miniobsidian.wikilink")
  local link = type(input) == "table" and input or wikilink.parse(input)
  if not link then
    core.notify("无法解析链接目标", vim.log.levels.WARN)
    return
  end

  local function jump(path)
    local line, fragment_err = wikilink.locate_fragment(path, link)
    vim.schedule(function()
      vim.cmd("edit " .. vim.fn.fnameescape(path))
      if line then
        vim.api.nvim_win_set_cursor(0, { line, 0 })
      elseif fragment_err then
        core.notify("链接片段不存在: " .. (link.heading or ("^" .. link.block)), vim.log.levels.WARN)
      end
    end)
  end

  local resolved, resolve_err = wikilink.resolve(link, notes, core.config.vault_path)
  if resolved then
    jump(resolved.path)
    return
  end
  if resolve_err.code == "AMBIGUOUS_NOTE" then
    vim.ui.select(resolve_err.candidates, { prompt = "选择同名笔记:" }, function(choice)
      if choice then
        local selected = wikilink.resolve({ target = choice }, notes, core.config.vault_path)
        if selected then
          jump(selected.path)
        end
      end
    end)
    return
  end

  local target = link.target
  local bare = target:match("([^/]+)$")
  if not bare or bare == "" then
    core.notify("无法解析链接目标: " .. target, vim.log.levels.WARN)
    return
  end
  local parent_id = target:match("^(.*)/[^/]+$") or ""
  local directory, directory_err = path_policy.resolve(core.config.vault_path, parent_id, { allow_empty = true })
  if not directory then
    core.notify("链接创建路径不安全: " .. tostring(directory_err), vim.log.levels.ERROR)
    return
  end

  vim.schedule(function()
    vim.ui.input(
      { prompt = "笔记 '" .. target .. "' 不存在，按 Enter 确认创建（Esc 取消）: " },
      function(confirmation)
        if confirmation ~= nil then
          M._create_note(bare, directory.path, { note_id = bare })
        end
      end
    )
  end)
end

return M
