-- ============================================================
-- 文件名：image.lua
-- 模块职责：将 macOS 剪贴板中的文件或图片保存到 vault 的附件目录，
--           并在当前 buffer 的光标后插入对应的 Markdown 链接。
--           支持以下两类来源：
--           • Finder 中复制的任意文件（保留原格式，支持多文件）
--           • 截图 / 浏览器中复制的图片（通过 NSImage 转换）
--           使用 macOS 内置的 osascript（JXA）实现，无需安装第三方工具。
-- 依赖关系：miniobsidian（config）、macOS 内置 osascript（仅 macOS 有效）
--           lua/miniobsidian/scripts/paste_file.js（JXA 脚本）
--           Neovim >= 0.10（vim.system API）
-- 对外 API：M.paste_file(name)、M.resolve_for_snacks(_, src)
-- ============================================================
local M = {}
local path_policy = require("miniobsidian.path")
local fs = require("miniobsidian.fs")
local markdown_link = require("miniobsidian.markdown_link")

-- ── 平台检测（模块加载时一次性完成，避免每次调用重复检测）────────
local IS_MACOS = vim.fn.has("mac") == 1

-- JXA 脚本的绝对路径：与本模块同目录下的 scripts/paste_file.js。
-- debug.getinfo(1, "S").source 返回 "@/absolute/path/to/image.lua"，
-- sub(2) 去掉 "@" 前缀，match 取出目录部分。
-- 这样无论插件被安装在哪个路径都能正确定位脚本。
local _M_DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])")
local PASTE_SCRIPT = _M_DIR .. "scripts/paste_file.js"

-- 图片扩展名集合，用于决定最终 Markdown 链接使用 ![](path) 还是 [文件名](path)
local IMAGE_EXTENSIONS = {
  png = true,
  jpg = true,
  jpeg = true,
  gif = true,
  webp = true,
  heic = true,
  heif = true,
  tiff = true,
  bmp = true,
  svg = true,
}

--- 净化文件名主干：去掉路径分隔符、NUL、Windows 保留字符、路径遍历以及首尾空格/点。
---@param name string
---@return string
local function sanitize_name(name)
  name = tostring(name or "")
  -- 替换各类文件系统不安全字符为连字符，保留中文等非 ASCII 字符
  name = name:gsub('[<>:"/\\|?*%z]', "-")
  -- 防止路径遍历
  name = name:gsub("%.%.", "-")
  -- 路径段不能以点或空格结尾
  name = name:gsub("[%. ]+$", "")
  if name == "" then
    name = "file"
  end
  return name
end

--- 判断扩展名是否为图片格式。
---@param ext string
---@return boolean
local function is_image(ext)
  return ext ~= nil and ext ~= "" and IMAGE_EXTENSIONS[ext:lower()] == true
end

--- 为 directory 生成不重复的 filename。
-- 仅按目标扩展名作精确冲突检测：例如 diagram.png 已存在时，
-- diagram.jpg 仍可使用，避免不同格式的同名文件被误加后缀。
---@param directory string 目标目录绝对路径
---@param filename string 期望文件名（含扩展名）
---@return string
function M.unique_filename(directory, filename)
  local function exists(path)
    return vim.uv.fs_stat(path_policy.join(directory, path)) ~= nil
  end

  if not exists(filename) then
    return filename
  end

  local stem, ext = filename:match("^(.*)%.([^.]+)$")
  if not stem then
    stem = filename
    ext = nil
  end
  local suffix = 1
  while true do
    local candidate = stem .. "-" .. suffix .. (ext and "." .. ext or "")
    if not exists(candidate) then
      return candidate
    end
    suffix = suffix + 1
  end
end

--- 计算从 from_dir 到 to_path 的相对路径（纯 Lua 实现，无外部依赖）。
-- 算法：找最长公共目录前缀，用 "../" 向上回退，拼接目标剩余路径。
---@param from_dir string 起始目录（绝对路径）
---@param to_path  string 目标文件（绝对路径）
---@return string
local function relative_path(from_dir, to_path)
  return path_policy.relative(
    path_policy.realpath(from_dir) or path_policy.normalize(from_dir),
    path_policy.realpath(to_path) or path_policy.normalize(to_path)
  )
end

--- 从原始文件名中分离出主干与扩展名。
---@param original_name string|nil
---@return string|nil stem
---@return string|nil ext
local function parse_original_name(original_name)
  if not original_name or original_name == "" then
    return nil, nil
  end
  local stem = original_name:match("^(.*)%.[^.]*$") or original_name
  local ext = original_name:match("%.([^.]+)$") or ""
  return stem, ext:lower()
end

--- 将剪贴板中的文件或图片保存到 vault 附件目录，并在光标后插入 Markdown 链接。
--
-- 完整流程：
--   1. 平台检测：非 macOS 友好提示并退出。
--   2. 若 name 为 nil，弹出输入框让用户命名（留空则使用时间戳）。
--   3. 解析并创建附件目录，以及本次粘贴专用的临时子目录。
--   4. 调用 osascript JXA 脚本，由脚本把剪贴板内容写入临时目录并返回 JSON 元数据。
--   5. 遍历返回列表：净化文件名、去重、硬链接发布、生成相对路径、组装 Markdown。
--   6. 批量插入光标下方，并清理临时目录。
--
-- 边界情况：
--   • 非 macOS：友好提示，不报错。
--   • 剪贴板无文件/图片：osascript 返回非零退出码，发出 WARN 并退出。
--   • 多文件：每个文件生成独立链接，按原始文件名命名。
--   • 单文件 + 用户命名：使用用户命名，扩展名由剪贴板内容决定。
--   • buffer 未保存（无路径）：使用 vault 相对路径作为回退。
--   • osascript 脚本缺失：发出 ERROR 并退出。
---@param name? string 文件名主干（不含扩展名；为 nil 时弹出输入框）
function M.paste_file(name)
  -- 非 macOS 系统：功能不可用，友好提示后静默返回
  if not IS_MACOS then
    vim.notify("[miniobsidian] Pasting attachments is only supported on macOS", vim.log.levels.WARN)
    return
  end

  -- 防御性检查：脚本文件是否存在（安装损坏时的兜底）
  if vim.fn.filereadable(PASTE_SCRIPT) == 0 then
    vim.notify(
      "[miniobsidian] Internal error: paste_file.js not found, please reinstall the plugin\nPath: " .. PASTE_SCRIPT,
      vim.log.levels.ERROR
    )
    return
  end

  local cfg = require("miniobsidian").config

  --- 执行附件保存与链接插入的核心逻辑。
  ---@param file_name string 用户输入的文件名主干（prompt 已预填时间戳，此处仅作空值兜底）
  local function do_paste(file_name)
    -- 解析附件目录（允许 attachments_folder 为空，即直接放在 vault 根目录）
    local directory, directory_err = path_policy.resolve(cfg.vault_path, cfg.attachments_folder, { allow_empty = true })
    if not directory then
      vim.notify("[miniobsidian] Attachment directory is unsafe: " .. tostring(directory_err), vim.log.levels.ERROR)
      return
    end
    local attach_dir = directory.path
    vim.fn.mkdir(attach_dir, "p")

    -- 在附件目录下创建本次粘贴专用的临时目录，确保与最终目标在同一文件系统，
    -- 方便后续使用硬链接原子发布。
    local temp_dir = path_policy.join(attach_dir, ".miniobsidian-paste-" .. tostring(vim.uv.hrtime()))
    vim.fn.mkdir(temp_dir, "p")

    -- ── 调用 osascript JXA 脚本 ────────────────────────────
    -- 脚本负责把剪贴板内容写入 temp_dir，并通过 stdout 返回 JSON 元数据数组。
    -- 使用列表形式传参，路径中的空格等特殊字符由 OS 进程 API 处理，无需 shell 转义。
    local proc = vim.system({ "osascript", "-l", "JavaScript", PASTE_SCRIPT, temp_dir }, { text = true }):wait()

    if proc.code ~= 0 then
      vim.fn.delete(temp_dir, "rf")
      -- 解析 stderr 中的错误关键字，给出可读提示
      local err = proc.stderr or ""
      if err:find("NO_CONTENT") then
        vim.notify("[miniobsidian] Clipboard contains no files or images (or unsupported format)", vim.log.levels.WARN)
      elseif err:find("READ_FAILED") then
        vim.notify("[miniobsidian] Failed to read source file, please check file permissions", vim.log.levels.ERROR)
      elseif err:find("WRITE_FAILED") then
        vim.notify(
          "[miniobsidian] Failed to write temporary file, please check directory permissions: " .. attach_dir,
          vim.log.levels.ERROR
        )
      elseif err:find("TIFF_FAILED") or err:find("BITMAP_FAILED") or err:find("CONVERT_FAILED") then
        vim.notify(
          "[miniobsidian] Image format conversion failed; clipboard content may not be a standard image",
          vim.log.levels.ERROR
        )
      else
        local first_line = err:match("[^\n]+") or "Unknown error"
        vim.notify("[miniobsidian] Failed to save attachment: " .. first_line, vim.log.levels.ERROR)
      end
      return
    end

    -- 解析 JXA 返回的 JSON 元数据数组
    local decode_ok, items = pcall(vim.json.decode, proc.stdout or "")
    if not decode_ok or type(items) ~= "table" or #items == 0 then
      vim.fn.delete(temp_dir, "rf")
      vim.notify("[miniobsidian] Failed to parse clipboard response data", vim.log.levels.ERROR)
      return
    end

    local md_lines = {}
    local saved_files = {}

    for _, item in ipairs(items) do
      local ext = (item.ext or ""):lower()
      local original_stem = parse_original_name(item.original_name)
      local stem

      -- 命名优先级：单文件 + 用户输入 > 原始文件名 > 时间戳
      if #items == 1 and file_name and file_name ~= "" then
        stem = file_name
      elseif original_stem and original_stem ~= "" then
        stem = original_stem
      else
        stem = os.date("attachment-%Y%m%d-%H%M%S")
      end

      stem = sanitize_name(stem)

      local filename = stem .. (ext ~= "" and "." .. ext or "")
      filename = M.unique_filename(attach_dir, filename)

      local abs_path = path_policy.join(attach_dir, filename)
      local temp_path = item.temp_path

      -- JXA 先写入临时文件，再通过 hard link 排他发布。
      -- hard link 在目标已存在时返回 EEXIST，因此即使发生并发竞争也不会覆盖原文件。
      local published, publish_err = fs.link_exclusive(temp_path, abs_path)
      fs.unlink(temp_path)

      if published == false then
        vim.notify("[miniobsidian] Attachment target already exists, please retry: " .. abs_path, vim.log.levels.WARN)
      elseif published == nil then
        vim.notify("[miniobsidian] Failed to finalize attachment: " .. tostring(publish_err), vim.log.levels.ERROR)
      else
        table.insert(saved_files, abs_path)

        -- ── 计算相对路径 ──────────────────────────────────────
        -- 相对路径可在 vault 移动位置后继续有效，与 Obsidian 桌面端行为一致。
        local buf_dir = vim.fn.expand("%:p:h")
        local rel_path
        if buf_dir and buf_dir ~= "" then
          rel_path = relative_path(buf_dir, abs_path)
        else
          rel_path = directory.logical == "" and filename or (directory.logical .. "/" .. filename)
        end

        -- 图片使用 ![](path)，其他文件使用 [文件名](path)
        local link
        if is_image(ext) then
          link = string.format("![](%s)", markdown_link.encode_path(rel_path))
        else
          link = string.format("[%s](%s)", markdown_link.escape_label(filename), markdown_link.encode_path(rel_path))
        end
        table.insert(md_lines, link)
      end
    end

    -- 清理本次粘贴的临时目录（包含未被链接的残留文件）
    vim.fn.delete(temp_dir, "rf")

    -- 批量插入生成的 Markdown 链接到光标下方，并将光标移到新行末尾
    if #md_lines > 0 then
      local row = vim.api.nvim_win_get_cursor(0)[1]
      vim.api.nvim_buf_set_lines(0, row, row, false, md_lines)
      vim.api.nvim_win_set_cursor(0, { row + #md_lines, 0 })
    end

    if #saved_files > 0 then
      local msg
      if #saved_files == 1 then
        msg = "[miniobsidian] Attachment saved: " .. saved_files[1]
      else
        msg = "[miniobsidian] Saved " .. #saved_files .. " attachments"
      end
      vim.notify(msg, vim.log.levels.INFO)
    end
  end

  -- 根据参数决定是否弹出交互输入框
  if name ~= nil then
    do_paste(name)
  else
    vim.ui.input({
      prompt = "Attachment file name (without extension): ",
      default = os.date("attachment-%Y%m%d-%H%M%S"),
    }, function(input)
      if input ~= nil then
        do_paste(input)
      end
    end)
  end
end

--- 解析 Obsidian wikilink 格式的图片引用，供 snacks.nvim image 使用。
-- 匹配 ![[image.png]] 中的裸文件名，在整个 vault 内递归查找实际路径。
-- 有路径分隔符的 src（如 ./img/foo.png）返回 nil，交由 snacks 默认逻辑处理。
---@param _ any snacks 传入的 ctx 对象（本函数不使用）
---@param src string 图片引用字符串（如 "image.png"）
---@return string|nil 图片文件的绝对路径，或 nil 表示未找到/不处理
function M.resolve_for_snacks(_, src)
  if src:find("/") or src:find("\\") then
    return nil
  end
  local cfg = require("miniobsidian").config
  local vault_path = cfg.vault_path
  if not vault_path or vault_path == "" then
    return nil
  end
  local found = vim.fs.find(src, { path = vault_path, type = "file", limit = 1 })
  return found[1]
end

return M
