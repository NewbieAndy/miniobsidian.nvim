-- ============================================================
-- 文件名：init.lua
-- 模块职责：miniobsidian.nvim 的核心模块，负责保存插件全局配置、
--           维护 vault 内笔记路径的扫描缓存，并提供路径工具函数。
--           其他所有子模块均通过 require("miniobsidian").config 读取配置。
-- 依赖关系：无外部插件依赖；仅使用 Neovim 内置 API（vim.fn、vim.api）
-- 对外 API：M.setup(opts)、M.get_all_notes(force)、M.invalidate_cache()、
--           M.note_stem(path)、M.in_vault(path)
-- ============================================================
local M = {}

-- ──────────────────────────────────────────────
-- 类型声明（供 LuaLS/neodev 静态分析使用）
-- ──────────────────────────────────────────────

---@class MiniObsidian.Config
---@field vaults_parent? string vault 父目录路径（可选；支持 ~ 展开；留空时若 auto_discover 为 true 则自动从 Obsidian 官方配置发现）
---@field default_vault? string 默认激活的 vault 目录名（省略时使用稳定排序后的第一个）
---@field auto_discover boolean 当 vaults_parent 为空时，是否自动从 Obsidian 官方 obsidian.json 发现 vault（默认 true）
---@field sync_obsidian_config boolean 确定活跃 vault 后，是否自动同步该 vault 内 .obsidian/*.json 配置到插件（默认 true）
---@field notes_subdir string   新建笔记存放的子目录（相对当前活跃 vault）
---@field dailies_folder string 每日笔记目录（相对当前活跃 vault）
---@field daily_template string Daily Note 模板的 Vault 相对 Note ID
---@field daily_default_content string 未配置模板时写入的新 Daily Note 内容（默认空）
---@field templates_folder string 模板文件所在目录（相对当前活跃 vault）
---@field attachments_folder string 图片等附件目录（相对当前活跃 vault）
---@field daily_date_format string os.date 格式字符串，用于每日笔记文件名及 frontmatter 日期
---@field change_cwd_on_switch boolean 切换 Vault 时是否设置当前 tab 的 cwd（默认 false）
---@field picker_scope "notes"|"vault" quick switch/search 的范围
---@field note_id_func fun(title: string): string 将标题转为文件名 ID 的函数
---@field checkbox_states string[] checkbox 循环切换状态列表（如 { " ", "/", "x", "-" }）
---@field vault_path string 当前活跃 vault 的绝对路径（运行时内部字段，由 setup 自动派生，请勿手动设置）
---@field after_note_open? fun(path: string, opts: table) 笔记文件成功打开后的回调（可选）。插件不执行任何全局副作用，由用户决定是否切换根目录或刷新文件树

-- ──────────────────────────────────────────────
-- 默认配置
-- ──────────────────────────────────────────────

--- 插件默认配置，用户通过 M.setup(opts) 覆盖其中的部分字段。
-- vault_path 为运行时内部字段，由 setup() 从 vaults_parent 扫描派生，无需手动设置。
local function new_default_config()
  return {
    vaults_parent = "",
    default_vault = "",
    auto_discover = true, -- vaults_parent 为空时，自动从 Obsidian 官方配置发现 vault
    sync_obsidian_config = true, -- 确定活跃 vault 后，自动同步该 vault 内 .obsidian/*.json 配置
    vault_path = "", -- 内部字段：当前活跃 vault 的绝对路径，由 setup() 自动设置
    notes_subdir = "Notes",
    dailies_folder = "",
    daily_template = "",
    daily_default_content = "",
    templates_folder = "Templates",
    attachments_folder = "Assets",
    daily_date_format = "%Y-%m-%d",
    change_cwd_on_switch = false,
    picker_scope = "notes",

    --- Checkbox 循环切换状态列表（按顺序循环）。
    -- 默认覆盖 Obsidian 最常用的 4 种状态：未完成→进行中→已完成→已取消。
    -- 可自定义：设为 { " ", "x" } 即回退到经典双态切换。
    checkbox_states = { " ", "x" },

    ---@type fun(name: string, path: string)|nil
    on_vault_switch = nil,

    ---@type fun(path: string, opts: table)|nil
    after_note_open = nil,

    --- 默认笔记 ID 函数：将标题转换为适合作文件名的小写 slug。
    -- 规则：保留中文、ASCII 字母数字、空格 → 空格变 "-" → 转小写。
    -- 示例：
    --   "Hello World"  → "hello-world"
    --   "我的笔记 2024" → "我的笔记-2024"
    --   "A & B!"       → "a-b"  （& 和 ! 被剔除后两侧空格合并为单个连字符）
    ---@param title string 笔记标题
    ---@return string id  用作文件名的 slug
    note_id_func = function(title)
      -- pattern 说明：
      --   %w                   → ASCII 字母和数字（[a-zA-Z0-9]）
      --   %s                   → 空白字符（空格、Tab 等）
      --   \u{2E80}-\u{9FFF}   → CJK 部首补充、笔画、汉字扩展A、康熙字典部首、
      --                          注音符号、平假名、片假名、基本 CJK 统一汉字
      --   \u{AC00}-\u{D7AF}   → 韩语谚文音节块
      --   \u{F900}-\u{FAFF}   → CJK 兼容汉字
      -- 取反（[^ ...]）意味着删掉以上范围以外的所有字符（标点、特殊符号等）
      local id = title:gsub("[^%w%s\u{2E80}-\u{9FFF}\u{AC00}-\u{D7AF}\u{F900}-\u{FAFF}]", "")

      -- 将一个或多个连续空白替换为单个连字符，生成 kebab-case 风格 slug
      id = id:gsub("%s+", "-")

      -- string.lower 仅影响 ASCII 范围，中文字符不受影响
      id = id:lower()
      return id
    end,
  }
end

function M.default_config()
  return new_default_config()
end

M.config = new_default_config()

---@param config MiniObsidian.Config
---@return string[]
function M.validate_config(config)
  local errors = {}
  local function add(condition, message)
    if not condition then
      errors[#errors + 1] = message
    end
  end

  add(type(config.vaults_parent) == "string", "vaults_parent 必须是字符串")
  add(type(config.default_vault) == "string", "default_vault 必须是字符串")
  add(type(config.auto_discover) == "boolean", "auto_discover 必须是 boolean")
  add(type(config.sync_obsidian_config) == "boolean", "sync_obsidian_config 必须是 boolean")
  add(type(config.change_cwd_on_switch) == "boolean", "change_cwd_on_switch 必须是 boolean")
  add(config.picker_scope == "notes" or config.picker_scope == "vault", "picker_scope 必须是 notes 或 vault")
  add(type(config.daily_date_format) == "string" and config.daily_date_format ~= "", "daily_date_format 不能为空")
  add(type(config.note_id_func) == "function", "note_id_func 必须是函数")
  add(type(config.checkbox_states) == "table" and #config.checkbox_states > 0, "checkbox_states 不能为空")

  local path_policy = require("miniobsidian.path")
  for _, key in ipairs({ "notes_subdir", "dailies_folder", "templates_folder", "attachments_folder" }) do
    local value = config[key]
    local valid = type(value) == "string" and path_policy.validate_logical(value, { allow_empty = true })
    add(valid ~= nil and valid ~= false, key .. " 必须是安全的 Vault 相对路径")
  end

  return errors
end

-- ──────────────────────────────────────────────
-- 笔记路径扫描缓存
-- ──────────────────────────────────────────────

--- 缓存：存储上一次 globpath 扫描的结果（string[] 或 nil）
local _cache = nil

--- 缓存时间戳：上次扫描时 os.time() 的值（秒级 Unix 时间戳）
local _cache_time = 0

--- 缓存版本号：每次重扫或失效递增，供补全源精确判断是否需要重建 items。
local _cache_stamp = 0

--- 缓存有效期（秒）。设为 5 秒：
--   • 补全触发非常频繁，避免每次按键都调用 globpath（磁盘 I/O）。
--   • 5 秒足够短，不会让新建/删除的笔记长时间不可见。
--   • 写入文件时会主动调用 invalidate_cache()，正常情况几乎不会用到过期。
local CACHE_TTL = 5

-- ──────────────────────────────────────────────
-- 公开 API
-- ──────────────────────────────────────────────

--- 当前活跃 vault 的目录名（供 lualine 等状态栏插件读取）。
-- 由 setup() 初始化，切换 vault 后由 vault.do_switch() 更新。
M.active_vault_name = ""

--- 获取 vault 内所有 .md 文件的绝对路径列表。
-- 结果带 5 秒内存缓存，避免频繁调用 globpath 造成的 I/O 开销。
-- 副作用：若 vault_path 目录不存在，发出 WARN 级通知并返回空表。
---@param force? boolean 传 true 时跳过缓存，强制重新扫描（例如手动刷新场景）
---@return string[] paths 所有 .md 文件的绝对路径列表（可能为空表）
function M.get_all_notes(force)
  local now = os.time()

  -- 命中缓存的条件：未强制刷新 AND 缓存非空 AND 未过期
  if not force and _cache and (now - _cache_time) < CACHE_TTL then
    return _cache
  end

  local vault = M.config.vault_path
  local path_policy = require("miniobsidian.path")

  -- 检查 vault 目录是否存在，isdirectory 返回 0 表示不存在或是文件
  if vim.fn.isdirectory(vault) == 0 then
    vim.notify("[miniobsidian] vault_path 不存在: " .. vault, vim.log.levels.WARN)
    return {}
  end

  -- globpath 第三参数 false：不忽略通配符特殊字符
  -- globpath 第四参数 true ：返回 table 而非换行分隔的字符串（Neovim 扩展）
  -- "**/*.md" 递归匹配所有子目录下的 .md 文件
  local raw = vim.fn.globpath(vault, "**/*.md", false, true)

  -- 过滤：排除路径中含有隐藏目录段（以 "." 开头）的文件，
  -- 避免 .obsidian/、.git/ 等目录下的 .md 文件混入笔记列表。
  local notes = {}
  -- 去掉 vault 末尾斜杠后加 "/"，确保无论 vault_path 是否带尾斜杠都能正确截取相对路径
  for _, p in ipairs(raw) do
    local resolved = path_policy.resolve(vault, p, { allow_absolute = true })
    if resolved then
      notes[#notes + 1] = p
    end
  end

  _cache = notes
  _cache_time = now
  _cache_stamp = _cache_stamp + 1
  return _cache
end

--- 主动使笔记缓存失效。
-- 在新建、删除笔记后调用，确保下次 get_all_notes() 能看到最新文件列表。
-- 副作用：将 _cache 置 nil，_cache_time 归零。
function M.invalidate_cache()
  _cache = nil
  _cache_time = 0
  _cache_stamp = _cache_stamp + 1
end

--- 返回当前笔记路径缓存版本（供 completion.lua 判断 items 缓存是否需要重建）。
-- 每次 invalidate_cache() 或重新扫描都会递增，避免同一秒内切换 vault 复用旧候选。
-- 通过公开方法暴露，而非让外部模块直接访问私有变量 _cache_time。
---@return number 缓存版本号
function M.get_cache_stamp()
  return _cache_stamp
end

--- 从笔记绝对路径中提取文件 stem（文件名去掉 .md 后缀）。
-- 示例："/vault/Notes/hello-world.md" → "hello-world"
-- 边界情况：若路径不包含 .md 后缀，原样返回整条路径（避免返回 nil）。
---@param path string 笔记的绝对路径
---@return string stem 文件名（不含 .md）
function M.note_stem(path)
  -- pattern 说明：
  --   [^/\\]+ → 匹配最后一段路径（文件名），贪婪匹配非斜杠字符
  --   %.md$   → 匹配字符串末尾的字面 ".md"（% 转义 . 为普通字符）
  return path:match("([^/\\]+)%.md$") or path
end

--- 判断给定路径是否位于 vault 内部。
-- 用于 completion、autocmd 等场景，只对 vault 内的 buffer 启用插件功能。
-- 边界情况：
--   • path 为 nil 或空字符串时返回 false（避免 nil 访问错误）
--   • path 恰好等于 vault_path 本身时返回 true（打开 vault 根目录的情况）
---@param path string 要检查的文件路径（通常来自 nvim_buf_get_name）
---@return boolean 是否在 vault 内
function M.in_vault(path)
  if not path or path == "" then
    return false
  end
  return require("miniobsidian.path").is_within_vault(M.config.vault_path, path)
end

--- 统一通知入口。
-- 自动添加 [miniobsidian] 前缀，确保所有通知风格一致。
---@param msg string 通知内容
---@param level? number vim.log.levels 级别（默认 INFO）
function M.notify(msg, level)
  vim.notify("[miniobsidian] " .. msg, level or vim.log.levels.INFO)
end

--- 将字符串转义为合法的 YAML 双引号字符串值。
-- 反斜杠和双引号需要转义，防止破坏 frontmatter 结构。
---@param s string 原始字符串
---@return string 被双引号包裹、已转义的值
function M.yaml_quote(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

---@param path string 刚打开的笔记文件绝对路径
---@param opts? { switch_root?: boolean }
function M.after_note_open(path, opts)
  opts = opts or {}

  vim.api.nvim_exec_autocmds("User", {
    pattern = "MiniObsidianNoteOpened",
    data = { path = path, opts = opts },
  })

  local cb = M.config.after_note_open
  if cb then
    pcall(cb, path, opts)
  end
end

--- 插件入口函数：合并用户配置、扫描 vault 列表并完成初始化。
-- 必须在 Neovim 启动过程中调用（通常在 lazy.nvim 的 config 回调里）。
-- 副作用：
--   1. 使用 vim.tbl_deep_extend 深度合并，用户只需提供要覆盖的字段。
--   2. 展开 vaults_parent 中的 ~ 为实际 home 目录。
--   3. 扫描 vaults_parent 下含 .obsidian/ 的子目录，或从 Obsidian 官方配置自动发现。
--   4. 按 default_vault 或首个结果设置内部字段 config.vault_path 和 active_vault_name。
--   5. 若 sync_obsidian_config 为 true，读取活跃 vault 内 .obsidian/*.json 并同步到配置。
--   6. 触发 User MiniObsidianSetup 事件，plugin/miniobsidian.lua 监听该事件
--      以注册 BufWritePost autocmd（延迟注册，确保 config 已就绪）。
---@param opts? MiniObsidian.Config 用户配置（部分字段覆盖默认值）
function M.setup(opts)
  opts = opts or {}

  -- 记录用户显式设置的配置 key，后续自动同步时跳过这些 key
  -- 确保用户手动值优先级始终高于自动发现/同步的值
  M._user_config_keys = {}
  for k, _ in pairs(opts) do
    M._user_config_keys[k] = true
  end

  M.config = vim.tbl_deep_extend("force", new_default_config(), opts)
  M.active_vault_name = ""
  M.invalidate_cache()

  local config_errors = M.validate_config(M.config)
  if #config_errors > 0 then
    for _, message in ipairs(config_errors) do
      M.notify("配置无效: " .. message, vim.log.levels.ERROR)
    end
    return false, config_errors
  end

  -- 展开 vaults_parent 中的 ~ 和环境变量
  M.config.vaults_parent = vim.fn.expand(M.config.vaults_parent)

  -- 扫描 vaults_parent，发现有效 vault 并设置初始活跃 vault
  local vault = require("miniobsidian.vault")
  vault.refresh_vaults() -- 清除旧缓存，确保本次 setup 使用最新扫描结果
  local vaults = vault.list_vaults(M.config.vaults_parent)

  if #vaults == 0 then
    vim.notify(
      "[miniobsidian] 未找到有效的 vault。解决方法：\n"
        .. "  1. 在 Obsidian 客户端中新建或打开一个 vault\n"
        .. "  2. 手动配置 vaults_parent 指向 vault 的父目录",
      vim.log.levels.ERROR
    )
  else
    -- 默认使用稳定排序后的第一个 vault
    local target = vaults[1]

    -- 若用户指定了 default_vault，尝试匹配
    if M.config.default_vault ~= "" then
      local found = false
      for _, v in ipairs(vaults) do
        if v.name == M.config.default_vault then
          target = v
          found = true
          break
        end
      end
      if not found then
        vim.notify(
          "[miniobsidian] default_vault '"
            .. M.config.default_vault
            .. "' 未找到，使用第一个 vault："
            .. target.name,
          vim.log.levels.WARN
        )
      end
    end

    M.config.vault_path = target.path
    M.active_vault_name = target.name

    -- 同步 Obsidian vault 内配置（用户手动配置优先）
    if M.config.sync_obsidian_config then
      local ok, config_sync = pcall(require, "miniobsidian.config_sync")
      if ok then
        local overrides = config_sync.read_vault_config(target.path)
        for key, value in pairs(overrides) do
          if not M._user_config_keys[key] then
            M.config[key] = value
          end
        end
      end
    end
  end

  -- 触发自定义 User 事件，通知 plugin/miniobsidian.lua 注册后续 autocmd。
  vim.api.nvim_exec_autocmds("User", { pattern = "MiniObsidianSetup" })

  return true
end

return M
