-- ============================================================
-- 文件名：config_sync.lua
-- 模块职责：读取 Obsidian 官方配置文件，实现 vault 的自动发现
--           以及 vault 内配置（app.json、daily-notes.json）的同步。
--           完全独立于其他子模块，仅在 init.lua / vault.lua 中按需调用。
-- 依赖关系：无外部插件依赖；仅使用 Neovim 内置 API
-- 对外 API：M.discover_vaults()、M.read_vault_config(vault_path)、
--           M.moment_to_lua_date(moment_fmt)
-- ============================================================
local M = {}

-- ──────────────────────────────────────────────
-- 跨平台 obsidian.json 路径发现
-- ──────────────────────────────────────────────

--- 返回当前操作系统下所有可能的 obsidian.json 候选路径。
-- 按优先级排列：默认路径在前，特殊安装路径（Flatpak/Snap）在后。
-- 路径中可能包含 ~，调用方需用 vim.fn.expand 展开。
---@return string[] 候选路径列表
function M._obsidian_config_paths()
  local sysname = vim.loop.os_uname().sysname

  if sysname == "Darwin" then
    -- macOS：标准 Application Support 路径
    return {
      "~/Library/Application Support/obsidian/obsidian.json",
    }
  end

  if sysname == "Linux" then
    local home = os.getenv("HOME") or ""
    local candidates = {
      "~/.config/obsidian/obsidian.json",
    }
    -- Flatpak 安装路径
    table.insert(candidates, home .. "/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json")
    -- Snap 安装路径（固定子目录）
    table.insert(candidates, home .. "/snap/obsidian/current/.config/obsidian/obsidian.json")
    -- Snap 安装路径（带编号子目录，如 x1/）
    local snap_pattern = home .. "/snap/obsidian/*/.config/obsidian/obsidian.json"
    local ok, snap_matches = pcall(vim.fn.glob, snap_pattern, false, true)
    if ok and snap_matches and #snap_matches > 0 then
      for _, p in ipairs(snap_matches) do
        table.insert(candidates, p)
      end
    end
    return candidates
  end

  -- Windows 及其他：通过 %APPDATA% 环境变量
  local appdata = vim.fn.expand("$APPDATA")
  if appdata and appdata ~= "$APPDATA" then
    return { appdata .. "\\obsidian\\obsidian.json" }
  end

  return {}
end

-- ──────────────────────────────────────────────
-- Vault 自动发现
-- ──────────────────────────────────────────────

--- 从 Obsidian 官方配置文件中读取所有已注册的 vault。
-- 遍历 _obsidian_config_paths() 返回的候选路径，读取第一个存在的文件。
-- 返回格式与 vault.list_vaults() 一致：{ name: string, path: string }[]
-- 边界情况：文件不存在、解析失败时返回空表并发出 WARN 通知。
---@return {name: string, path: string}[] 发现的 vault 列表
function M.discover_vaults()
  local paths = M._obsidian_config_paths()

  for _, raw_path in ipairs(paths) do
    local expanded = vim.fn.expand(raw_path)
    if vim.fn.filereadable(expanded) == 1 then
      local ok, vaults = pcall(M._parse_obsidian_json, expanded)
      if ok and #vaults > 0 then
        return vaults
      end
    end
  end

  return {}
end

--- 解析 obsidian.json 文件内容，提取 vault 列表。
-- 默认 vault 选择规则：
--   1. 若某个 vault 带有 open = true，将其排在列表首位（作为默认）
--   2. 否则按名称字母序排列，第一个作为默认
-- 内部函数；被 discover_vaults() 调用。
---@param path string obsidian.json 的绝对路径
---@return {name: string, path: string}[] vault 列表
function M._parse_obsidian_json(path)
  local content = vim.fn.readfile(path)
  if not content or #content == 0 then
    return {}
  end

  local ok, parsed = pcall(vim.json.decode, table.concat(content, "\n"))
  if not ok or type(parsed) ~= "table" or type(parsed.vaults) ~= "table" then
    vim.notify("[miniobsidian] 无法解析 Obsidian 配置文件: " .. path, vim.log.levels.WARN)
    return {}
  end

  local open_vaults = {}
  local vaults = {}

  for _, entry in pairs(parsed.vaults) do
    if type(entry) == "table" and type(entry.path) == "string" and entry.path ~= "" then
      local vault_path = entry.path
      -- 统一路径分隔符（Windows 反斜杠 → 正斜杠）
      vault_path = vault_path:gsub("\\", "/")
      -- 去除末尾斜杠
      vault_path = vault_path:gsub("/+$", "")
      local name = vim.fn.fnamemodify(vault_path, ":t")
      local v = { name = name, path = vault_path }

      if entry.open == true then
        table.insert(open_vaults, v)
      else
        table.insert(vaults, v)
      end
    end
  end

  -- 多个 Obsidian 客户端可同时让多个 vault 标记为 open=true。
  -- open vault 只影响默认排序，不能吞掉其它同样打开中的 vault。
  table.sort(open_vaults, function(a, b)
    return a.name < b.name
  end)
  table.sort(vaults, function(a, b)
    return a.name < b.name
  end)

  for i = #open_vaults, 1, -1 do
    table.insert(vaults, 1, open_vaults[i])
  end

  return vaults
end

-- ──────────────────────────────────────────────
-- Vault 内配置同步
-- ──────────────────────────────────────────────

--- 读取指定 vault 内的 Obsidian 配置文件，返回可同步到插件配置的覆盖值。
-- 读取的文件：
--   • .obsidian/app.json        → notes_subdir（newFileFolderPath）
--   • .obsidian/daily-notes.json → dailies_folder、daily_date_format
-- 用户手动配置的值优先级高于自动同步；调用方负责过滤。
---@param vault_path string vault 的绝对路径
---@return {notes_subdir?: string, dailies_folder?: string, daily_date_format?: string, daily_template?: string} 覆盖值表
function M.read_vault_config(vault_path)
  local overrides = {
    dailies_folder = "",
    daily_date_format = "%Y-%m-%d",
    daily_template = "",
  }

  -- 读取 app.json：新笔记默认存放位置
  local app_config_path = vault_path .. "/.obsidian/app.json"
  if vim.fn.filereadable(app_config_path) == 1 then
    local ok, app_config = M._read_json_file(app_config_path)
    if ok and type(app_config) == "table" then
      if app_config.newFileLocation == "folder" and app_config.newFileFolderPath then
        overrides.notes_subdir = app_config.newFileFolderPath
      elseif app_config.newFileLocation == "root" then
        overrides.notes_subdir = ""
      end
    end
  end

  -- 读取 daily-notes.json：日记目录和日期格式
  local daily_config_path = vault_path .. "/.obsidian/daily-notes.json"
  if vim.fn.filereadable(daily_config_path) == 1 then
    local ok, daily_config = M._read_json_file(daily_config_path)
    if ok and type(daily_config) == "table" then
      if type(daily_config.folder) == "string" then
        overrides.dailies_folder = daily_config.folder
      end
      if type(daily_config.template) == "string" then
        overrides.daily_template = daily_config.template
      end
      if daily_config.format and daily_config.format ~= "" then
        local lua_fmt = M.moment_to_lua_date(daily_config.format)
        if lua_fmt then
          overrides.daily_date_format = lua_fmt
        end
      end
    end
  end

  return overrides
end

--- 安全读取 JSON 文件并解析。
-- 内部辅助函数。
---@param path string JSON 文件绝对路径
---@return boolean ok 是否成功
---@return table|string result 成功时返回解析后的表，失败时返回错误信息
function M._read_json_file(path)
  local lines = vim.fn.readfile(path)
  if not lines or #lines == 0 then
    return false, "empty file"
  end
  local ok, parsed = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok then
    return false, tostring(parsed)
  end
  if type(parsed) ~= "table" then
    return false, "not a table"
  end
  return true, parsed
end

-- ──────────────────────────────────────────────
-- Moment.js 日期格式 → Lua os.date 格式
-- ──────────────────────────────────────────────

--- 将 Moment.js 风格日期格式字符串转换为 Lua os.date 格式。
-- 采用两遍替换策略：先用唯一占位符替换 Moment 标记，避免级联替换错误
--（例如 "January" 中的 "a" 被错误替换）。
--
-- 支持的 Moment 标记：
--   YYYY → %Y    YY → %y    MMMM → %B    MMM → %b
--   MM → %m      DD → %d    dddd → %A    ddd → %a
--   HH → %H      hh → %I    mm → %M      ss → %S
--   A → %p       a → %p
--
-- 不支持的标记（如 Moment 的 Do、wo、Qo 等）会保留原样，
-- 导致 os.date 输出原文字符；调用方可据此判断转换是否完全成功。
---@param moment_fmt string Moment.js 格式字符串
---@return string|nil lua_fmt 转换后的 Lua 格式字符串；若输入无效返回 nil
function M.moment_to_lua_date(moment_fmt)
  return require("miniobsidian.datetime").moment_to_lua(moment_fmt)
end

return M
