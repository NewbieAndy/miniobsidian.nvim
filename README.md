# miniobsidian.nvim

<div align="center">

**轻量、快速的 Obsidian 工作流 Neovim 插件**

[![Neovim](https://img.shields.io/badge/Neovim-%3E%3D0.10.4-blueviolet?logo=neovim)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Made%20with-Lua-blue?logo=lua)](https://lua.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[English](README.en.md) · 中文

</div>

---

## 这是什么？

`miniobsidian.nvim` 是一个轻量、专注的 Neovim 插件，将 Obsidian 的核心工作流带入终端编辑器——没有多余的依赖，没有复杂的配置。它深度整合现代 Neovim 生态（[blink.cmp](https://github.com/Saghen/blink.cmp)、[snacks.nvim](https://github.com/folke/snacks.nvim)），提供流畅、键盘驱动的笔记体验。

**设计哲学：** 只提供每天真正用得到的功能——笔记创建、快速跳转、全文搜索、Wiki 链接导航、Checkbox 管理、图片粘贴、模板系统、每日笔记。不内置 Telescope 依赖，不预设任何快捷键（完全由用户掌控），懒加载友好，对启动性能几乎没有影响。

> **灵感来源：** [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim) —— 一个功能完整的 Obsidian Neovim 客户端。`miniobsidian.nvim` 采用更轻量的设计哲学：无 Telescope 依赖、无复杂事件系统，只保留每天真正用到的功能。如需功能更全面、久经考验的方案，推荐使用该插件。

### 与 obs-cli 的边界

Markdown Vault 是唯一内容事实源。Obsidian、[`obs-cli`](https://github.com/andy-neoaira/obs-cli) 与 `miniobsidian.nvim` 是操作同一 Vault 的同级客户端。

- `miniobsidian.nvim` 不强制依赖 `obs-cli`，所有基础功能在未安装 CLI 时仍完整可用。
- `obs-cli` 不依赖 Neovim；AI Agent 通过 CLI 和场景化 Skills 进行安全的分析、比较和更新。
- 两个项目共享 Vault、Wikilink、Daily Note 与并发写入规范，但不共享运行时依赖。
- CLI 已作为可选高级能力 Adapter 接入；插件同时校验 `obs-cli/v1`、
  `vault-contract/v1` 和所需 operation，不兼容时安全降级为纯插件模式。
- Obsidian 官方配置只用于只读发现和设置同步，插件私有配置由插件自身管理。

完整架构决策见 [`obs-cli` ADR-001：Agent-first 产品边界与三入口架构](https://github.com/andy-neoaira/obs-cli/blob/master/docs/architecture/ADR-001-agent-first-boundary.md)。

共同规范状态：`target_contract = vault-contract/v1`，
`implemented_contract = vault-contract/v1`。两项目通过同一组固定 fixture 验证路径、
Wikilink、Daily Note、Frontmatter 与并发更新约定；规则见
[`obs-cli` Vault 共同约定](https://github.com/andy-neoaira/obs-cli/blob/master/docs/spec/VAULT_CONVENTIONS.md)。

---

## 功能一览

### 核心功能

| 功能 | 详细说明 |
|------|---------|
| 🗂️ **多 Vault 支持** | 自动扫描或从 Obsidian 官方配置发现 vault；一键切换默认不修改 cwd，可显式启用安全的 tab-local cwd 或使用回调刷新文件树 |
| 📝 **快速创建笔记** | 自动生成 YAML frontmatter（`title`、`date`、`tags`）；支持自定义文件名生成函数；内置 slug 规则兼容中文（CJK）字符；新建时光标自动定位到正文起始行 |
| 📁 **目录感知创建** | 焦点在文件浏览器时（snacks explorer / neo-tree / nvim-tree / oil.nvim / netrw），在光标所在目录下新建笔记；光标在文件上则在同级目录创建；目标必须在当前 vault 内 |
| 🔀 **快速切换笔记** | 通过 `snacks.nvim` picker 模糊搜索并跳转 Markdown 笔记；默认 `notes_subdir`，可配置为全 Vault |
| 🔍 **全文搜索** | 基于 ripgrep 的笔记全文搜索，附带实时预览；默认 `notes_subdir`，可配置为全 Vault |
| 🔗 **Wiki 链接跳转** | `<CR>` 跳转 `[[链接]]`；支持别名、限定路径、heading 与 block ID；basename 重名时明确要求选择，不会静默打开错误笔记；找不到时可在目标目录创建 |
| ✅ **Checkbox 状态循环** | 默认双态 `[ ]` ↔ `[x]`，可配置为 `[ ]` → `[/]` → `[x]` → `[-]` 等多状态；普通列表项可自动升级，`clear()` 可还原为普通列表项 |
| 🔗 **Wiki 链接自动补全** | 输入 `[[` 时，blink.cmp 列出 vault 内所有笔记供模糊选择；同名笔记通常显示为 `父目录/名称`，并插入完整 Vault 相对路径；**悬停候选时显示笔记前 10 行预览** |
| ✅ **Checkbox 自动补全** | 输入 `- [`、`* [`、`+ [` 时，blink.cmp 弹出当前 `checkbox_states` 中配置的所有状态候选 |
| 🖼️ **图片粘贴** | macOS 专用、内置 JXA；截图/浏览器图片保存为 PNG/JPG/GIF，Finder 复制的图片文件可保留 WEBP/HEIC/HEIF/TIFF/BMP/SVG 等原格式；插入可迁移的相对路径链接 |
| 📄 **模板系统** | 从 `Templates/`（支持子目录）选择并插入模板；支持 6 个命名变量和 `{{date:FORMAT}}` 自定义日期；未知变量保留并警告 |
| 📅 **每日笔记** | 一键打开/创建今日笔记；同步 Obsidian Daily Notes 的目录、格式与模板；无模板时默认创建空文件，已有笔记只打开不覆盖 |
| 🛡️ **外部修改保护** | `checktime` + 文件监听发现外部变化；每次写入前校验磁盘 SHA-256 基线，持续聚焦期间也能阻止 stale write |
| 🧰 **可选 CLI 高级能力** | 兼容 `obs-cli/v1` 与 `vault-contract/v1`；提供 dry-run + revision/plan_hash 安全移动和只读 Vault 审计 |
| 🤖 **Agent 协作** | 构造有界 handoff payload；验收结构化 result，提供 changed-files 摘要、unified diff 和 dirty buffer 三方视图 |

---

### Checkbox 状态参考

以下是插件内置描述的 checkbox 状态（在自动补全候选中显示）。你可以在 `checkbox_states` 中自由组合任意子集：

默认配置只使用 `{ " ", "x" }`；其余状态需要显式加入 `checkbox_states`。

| 状态字符 | 含义 | Markdown 示例 |
|---------|------|--------------|
| ` `（空格） | 待办 | `- [ ] 待处理事项` |
| `/` | 进行中 | `- [/] 正在进行` |
| `x` | 已完成 | `- [x] 已完成` |
| `-` | 已取消 | `- [-] 已取消` |
| `>` | 已转移 | `- [>] 已转移` |
| `!` | 重要 | `- [!] 重要任务` |
| `?` | 疑问 | `- [?] 待确认` |

---

### 模板变量参考

| 变量 | 说明 | 示例输出 |
|------|------|---------|
| `{{date}}` | 当前日期（格式由 `daily_date_format` 决定） | `2024-01-15` |
| `{{time}}` | 当前时间（HH:MM） | `14:30` |
| `{{title}}` | 当前文件名（不含扩展名） | `my-note` |
| `{{filename}}` | 同 `{{title}}` | `my-note` |
| `{{yesterday}}` | 昨天日期 | `2024-01-14` |
| `{{tomorrow}}` | 明天日期 | `2024-01-16` |
| `{{date:FORMAT}}` | 自定义格式日期 | `{{date:YYYY/MM/DD}}` → `2024/01/15` |

> 所有变量均**大小写不敏感**（`{{Date}}`、`{{DATE}}`、`{{date}}` 均有效）。未知变量保留原文并发出 warning；昨天/明天按本地日历日期计算，可安全跨越夏令时边界。

`{{date:FORMAT}}` 支持以下格式令牌（兼容 Obsidian 风格）：

| 令牌 | 含义 | 令牌 | 含义 |
|------|------|------|------|
| `YYYY` | 四位年份 | `HH` | 小时（00–23） |
| `MM` | 月份（01–12） | `mm` | 分钟（00–59） |
| `DD` | 日期（01–31） | `ss` | 秒（00–59） |

---

## 依赖要求

| 依赖 | 用途 | 安装方式 |
|------|------|---------|
| **Neovim ≥ 0.10.4** | 必需；CI 同时验证 0.10.4 与 stable | — |
| [snacks.nvim](https://github.com/folke/snacks.nvim) | 快速切换和全文搜索必需；模板/vault 选择可回退到 `vim.ui.select` | lazy.nvim（可选） |
| [blink.cmp](https://github.com/Saghen/blink.cmp) | 自动补全（wiki 链接 + checkbox，**可选**） | lazy.nvim |
| `ripgrep` | 仅全文搜索需要 | `brew install ripgrep`（可选） |
| `osascript` | 图片粘贴（macOS 系统内置，仅 macOS 有效） | — |
| [`obs-cli`](https://github.com/andy-neoaira/obs-cli) | 安全移动、Vault 审计和内置 Agent handoff | 可选高级能力 |

健康检查：

```vim
:checkhealth miniobsidian
```

内置帮助：

```vim
:help miniobsidian
:help miniobsidian-zh
```

---

## 安装

### lazy.nvim（最简配置）

```lua
{
  "andy-neoaira/miniobsidian.nvim",
  lazy = true,
  ft = "markdown",
  cmd = {
    "ObsidianNew", "ObsidianNewHere", "ObsidianSwitchVault", "ObsidianSwitch",
    "ObsidianSearch", "ObsidianTemplate", "ObsidianNewTemplate", "ObsidianPasteImg",
    "ObsidianToday", "ObsidianSetup", "ObsidianResolveConflict", "ObsidianCLIRefresh",
    "ObsidianMove", "ObsidianVaultAudit", "ObsidianAgentAnalyze",
    "ObsidianAgentUpdate", "ObsidianAgentLastResult",
  },
  config = function()
    require("miniobsidian").setup()
    -- 零配置启动：自动从 Obsidian 官方配置发现 vault，并同步 vault 内设置
  end,
}
```

### lazy.nvim（完整配置，含 blink.cmp 自动补全）

以下内容可直接保存为一个返回插件列表的 Lua 文件，例如 `lua/plugins/miniobsidian.lua`：

```lua
return {
-- quick switch / search 使用的 picker
{
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    picker = { enabled = true },
  },
},

-- miniobsidian 主插件
{
  "andy-neoaira/miniobsidian.nvim",
  lazy = true,
  ft = "markdown",
  cmd = {
    "ObsidianNew", "ObsidianNewHere", "ObsidianSwitchVault", "ObsidianSwitch",
    "ObsidianSearch", "ObsidianTemplate", "ObsidianNewTemplate", "ObsidianPasteImg",
    "ObsidianToday", "ObsidianSetup", "ObsidianResolveConflict", "ObsidianCLIRefresh",
    "ObsidianMove", "ObsidianVaultAudit", "ObsidianAgentAnalyze",
    "ObsidianAgentUpdate", "ObsidianAgentLastResult",
  },
  keys = {
    -- 全局快捷键（任意文件类型均可触发，lazy 加载时也会生效）
    { "<leader>nn", function() require("miniobsidian.note").new_note() end,         desc = "Obsidian: 新建笔记" },
    { "<leader>na", function() require("miniobsidian.note").new_note_here() end,   desc = "Obsidian: 在文件树目录新建笔记" },
    { "<leader>no", function() require("miniobsidian.note").quick_switch() end,     desc = "Obsidian: 快速切换" },
    { "<leader>ns", function() require("miniobsidian.note").search() end,           desc = "Obsidian: 搜索笔记" },
    { "<leader>nS", function() require("miniobsidian.note").search(vim.fn.expand("<cword>")) end,
                                                                                    desc = "Obsidian: 搜索当前词" },
    { "<leader>nv", function() require("miniobsidian.vault").pick_and_switch() end, desc = "Obsidian: 切换 Vault" },
    { "<leader>nd", function() require("miniobsidian.daily").open_today() end,      desc = "Obsidian: 每日笔记" },
    { "<leader>nT", function() require("miniobsidian.template").new_template() end, desc = "Obsidian: 新建模板" },
    -- Markdown 专用快捷键（仅在 .md 文件生效）
    { "<leader>nt", function() require("miniobsidian.template").insert() end,            ft = "markdown", desc = "Obsidian: 插入模板" },
    { "<leader>np", function() require("miniobsidian.image").paste_img() end,            ft = "markdown", desc = "Obsidian: 粘贴图片" },
    { "<leader>nl", function() require("miniobsidian.checkbox").clear() end,             ft = "markdown", desc = "Obsidian: 恢复列表项" },
    { "<CR>",       function() require("miniobsidian.link").follow_link_or_toggle() end, ft = "markdown", desc = "Obsidian: 跟随链接 / 切换 Checkbox" },
  },
  config = function()
    require("miniobsidian").setup({
      -- vaults_parent 留空时，插件会自动从 Obsidian 官方配置发现 vault
      -- 如需手动指定，取消下行注释：
      -- vaults_parent = "~/Library/Mobile Documents/iCloud~md~obsidian/Documents",
      default_vault = "MyVault",
      notes_subdir  = "Notes",
      checkbox_states = { " ", "/", "x", "-" },
    })
  end,
},

-- 将 miniobsidian 注册为 blink.cmp 补全源
{
  "saghen/blink.cmp",
  version = "1.*", -- 固定稳定版；main 分支可能包含破坏性变更
  opts = function(_, opts)
    opts.sources = opts.sources or {}
    opts.sources.default = vim.list_extend(opts.sources.default or {}, { "miniobsidian" })
    opts.sources.providers = vim.tbl_deep_extend("force", opts.sources.providers or {}, {
      miniobsidian = {
        name = "MiniObsidian",
        module = "miniobsidian.completion",
        score_offset = 50,  -- 高于 buffer/snippets，保证 [[ 时笔记候选靠前
        -- 触发字符由 source 内的 get_trigger_characters() 方法声明，
        -- 此处无需重复设置 trigger_characters 字段
      },
    })
    return opts
  end,
},
}
```

---

## 配置项说明

```lua
require("miniobsidian").setup({
  -- ── 可选 ──────────────────────────────────────────────────────────────
  -- vault 父目录路径
  -- 插件自动扫描其下含 .obsidian/ 子目录的文件夹作为有效 vault
  -- 支持 ~ 展开；也适用于 iCloud Drive 同步路径
  -- 留空时，若 auto_discover 为 true，插件会自动从 Obsidian 官方配置发现 vault
  vaults_parent = "",

  -- 默认激活的 vault 名称
  -- 省略时：自动发现优先选择 Obsidian 标记为 open 的 vault；
  -- 手动扫描 vaults_parent 时选择按名称排序后的第一个 vault
  default_vault = "",

  -- 当 vaults_parent 为空时，是否自动从 Obsidian 官方 obsidian.json 发现 vault
  -- 默认 true；设为 false 则必须手动指定 vaults_parent
  auto_discover = true,

  -- 确定活跃 vault 后，是否自动同步该 vault 内 .obsidian/*.json 配置到插件
  -- 默认 true；同步 notes_subdir 以及 Daily Notes 的目录、格式和模板
  -- 用户手动配置的值优先级始终高于自动同步的值
  sync_obsidian_config = true,

  -- 新建笔记存放的子目录（相对于活跃 vault 根）
  -- 留空 "" 时直接存放在 vault 根目录
  -- 若 sync_obsidian_config 为 true，会自动读取 .obsidian/app.json 的 newFileFolderPath
  notes_subdir = "Notes",

  -- 每日笔记目录；留空 "" 时直接创建在 Vault 根目录
  -- 若 sync_obsidian_config 为 true，会自动读取 .obsidian/daily-notes.json 的 folder
  -- 该文件不存在或未配置 folder 时仍使用空字符串默认值
  dailies_folder = "",

  -- Daily Note 模板的 Vault 相对 Note ID；默认从 daily-notes.json 同步
  daily_template = "",

  -- 未配置模板时的新文件初始内容；默认空字符串
  daily_default_content = "",

  -- 模板目录（:ObsidianTemplate 从此处读取 .md 文件，支持子目录）
  templates_folder = "Templates",

  -- 图片等附件目录
  attachments_folder = "Assets",

  -- 日期格式（用于每日笔记文件名及 frontmatter `date:` 字段）
  -- 采用 Lua 的 os.date 格式字符串
  -- 若 sync_obsidian_config 为 true，会自动读取 .obsidian/daily-notes.json 的 format
  -- 并尝试将 Moment.js 格式转换为 Lua os.date 格式
  daily_date_format = "%Y-%m-%d",

  -- 外部修改策略："prompt"（默认）、"reload"（仅未修改 buffer 自动重载）或 "notify"
  external_change_mode = "prompt",
  external_check_interval_ms = 1000, -- FocusGained/BufEnter checktime 防抖
  external_watch_debounce_ms = 100,  -- Vault 文件系统事件防抖
  watch_external_changes = true,     -- 外部创建/删除/重命名时失效笔记缓存

  -- 快速切换/全文搜索范围："notes" 使用 notes_subdir；"vault" 使用整个 Vault
  picker_scope = "notes",

  -- 切换 Vault 默认不修改 cwd；设为 true 时只执行 tab-local :tcd
  change_cwd_on_switch = false,

  -- 可选回调；默认 nil
  on_vault_switch = nil, -- function(name, path) ... end
  after_note_open = nil, -- function(path, opts) ... end

  -- 可选 obs-cli adapter；插件本地功能始终不依赖 CLI
  -- false：禁用；"auto"：存在时异步探测（默认）；true：显式启用，失败在 health 中告警
  cli = {
    enabled = "auto",
    command = "obs-cli", -- 单个 executable 路径，不是 shell 命令字符串
    timeout_ms = 3000,
  },

  -- 可选 Agent handoff bridge；插件不绑定具体 Agent 框架
  agent = {
    handler = nil,               -- function(payload) ... end；默认未配置
    confirm_content = true,      -- 内存内容发送前预览确认
    large_selection_lines = 200, -- 大选区始终确认
  },

  -- Checkbox 循环状态序列（按配置顺序切换，可使用上方状态参考表中的任意字符）
  -- 极简双态：{ " ", "x" }
  -- 扩展版本：{ " ", "/", "x", "-", ">", "!", "?" }
  checkbox_states = { " ", "x" },

  -- 自定义笔记 ID（文件名）生成函数
  -- 默认规则：保留中文/英日韩文字、英文字母和数字，其余符号去除，空格转连字符，转小写
  -- 示例："Hello World"  → "hello-world"
  --       "我的笔记 2024" → "我的笔记-2024"
  note_id_func = function(title)
    local id = title:gsub("[^%w%s\u{2E80}-\u{9FFF}\u{AC00}-\u{D7AF}\u{F900}-\u{FAFF}]", "")
    id = id:gsub("%s+", "-")
    return id:lower()
  end,
})
```

### 自动发现与配置同步

当 `auto_discover = true`（默认）且 `vaults_parent` 留空时，插件会自动查找 Obsidian 官方配置文件（`obsidian.json`）并从中读取已注册的 vault 列表。支持以下平台：

- **macOS**：`~/Library/Application Support/obsidian/obsidian.json`
- **Linux**：`~/.config/obsidian/obsidian.json`，以及 Flatpak / Snap 安装路径
- **Windows**：`%APPDATA%\obsidian\obsidian.json`

当 `sync_obsidian_config = true`（默认）时，插件在确定活跃 vault 后会自动读取该 vault 内的 Obsidian 配置，并同步到插件配置中：

| 同步来源 | 字段 | 说明 |
|---------|------|------|
| `.obsidian/app.json` | `notes_subdir` | 读取 `newFileFolderPath`（当 `newFileLocation` 为 `folder` 时） |
| `.obsidian/daily-notes.json` | `dailies_folder` | 读取 `folder` |
| `.obsidian/daily-notes.json` | `daily_date_format` | 读取 `format` 并尝试将 Moment.js 格式转换为 Lua `os.date` 格式 |
| `.obsidian/daily-notes.json` | `daily_template` | 读取 `template`，按 Vault 相对 Note ID 安全解析 |

**配置优先级（从高到低）：**

1. 用户在 `setup()` 中**显式设置**的值 — 永远不被覆盖
2. 自动同步从 Obsidian 配置读取的值 — 仅在用户未显式设置时生效
3. 插件内置默认值

切换 vault 时（`:ObsidianSwitchVault`），若 `sync_obsidian_config` 为 true，插件会自动重新读取新 vault 的配置并应用。

### 行为说明

- `setup()` 每次都从默认配置重新构造；重复调用不会继承上一次的自定义字段。
- Vault 切换默认不再修改全局 cwd。需要 cwd 联动时启用 `change_cwd_on_switch = true`（tab-local），或使用 `on_vault_switch` / `after_note_open` 回调。
- Daily Note 默认目录为 Vault 根、无模板时创建空文件，行为与 Obsidian 官方配置和 `vault-contract/v1` 一致。
- 快速切换与搜索默认仍使用 `notes_subdir`；设置 `picker_scope = "vault"` 可覆盖整个 Vault。
- `obs-cli` 是可选高级能力。`auto` 模式只异步执行
  `capabilities --output json`；CLI 缺失、超时、非法 JSON、协议或 Vault 共同规范
  不兼容都不会影响插件本地功能。Adapter 只使用结构化 argv，不经过 shell 插值。
- `:ObsidianMove` 仅在 `note.get` 与 `note.move` capability 可用时工作。它会先读取
  revision、执行 dry-run 并展示完整计划，只有用户选择 `Apply` 后才携带
  `revision + plan_hash` 提交；未保存 buffer 会在任何 CLI 移动前被拒绝。
- `:ObsidianVaultAudit` 通过只读 `note.list` 打开当前 Vault 的 JSON 快照，作为后续
  审计/批量操作的只读入口，不会自动 apply。
- Agent handoff 通过用户配置的 `agent.handler(payload)` 适配任意 Agent 框架，
  不启动 shell。Payload 固定为 `miniobsidian.agent-handoff/v1`，包含请求元数据、
  Vault ID、当前笔记相对路径/revision、显式意图、权限边界和可选内存选区；
  默认禁止全 Vault 扫描。
- `:ObsidianAgentAnalyze` 使用只读权限与 `obsidian-knowledge-synthesis` Skill；
  dirty buffer 只允许经确认的内存只读分析。`:ObsidianAgentUpdate` 要求先保存
  buffer，并只授权当前路径给 `obsidian-safe-note-update`。当前内置 handoff
  需要兼容的 `obs-cli`：分析要求 `note.get`，更新要求 `note.get` 与 `note.patch`。
- Agent 完成后由集成层调用
  `require("miniobsidian.agent_result").handle(result)`。Result 使用
  `miniobsidian.agent-result/v1`：先显示 changed files/revision/摘要；多文件先选择，
  clean buffer 显示 unified diff，dirty buffer 显示 base / Agent disk / local
  三方视图，绝不自动选择版本。`PARTIAL_FAILURE` 等错误显示恢复清单。

---

## 用户命令

| 命令 | 参数 | 说明 |
|------|------|------|
| `:ObsidianNew[!] [标题]` | 可选 | 新建到 `notes_subdir`；`!` 向 `after_note_open` 传递 `switch_root=true` |
| `:ObsidianNewHere` | 无 | 在当前文件浏览器焦点目录下新建笔记（支持 snacks explorer / neo-tree / nvim-tree / oil.nvim / netrw） |
| `:ObsidianSwitch` | 无 | 打开笔记快速切换 picker |
| `:ObsidianSearch [关键词]` | 可选 | 打开全文搜索 picker；省略时以空查询启动 |
| `:ObsidianSwitchVault` | 无 | 弹出 vault 选择器并切换 |
| `:ObsidianTemplate` | 无 | 选择并插入模板 |
| `:ObsidianNewTemplate [名称]` | 可选 | 新建模板文件；省略则弹出输入框 |
| `:ObsidianPasteImg [文件名]` | 可选 | 粘贴剪贴板图片（macOS）；省略则弹出输入框 |
| `:ObsidianToday[!]` | 无 | 打开/创建今日笔记；`!` 向 `after_note_open` 传递 `switch_root=true` |
| `:ObsidianResolveConflict` | 无 | 处理当前笔记的外部修改：查看 diff、保留 buffer 或重新加载磁盘 |
| `:ObsidianCLIRefresh` | 无 | 异步刷新可选 obs-cli capability 缓存 |
| `:ObsidianMove [目标路径]` | 可选 | dry-run 预览并确认后安全移动当前笔记；需要 `note.get` / `note.move` |
| `:ObsidianVaultAudit` | 无 | 打开只读 Vault JSON 快照；需要 `note.list` |
| `:[range]ObsidianAgentAnalyze [意图]` | 可选 | 有界只读分析；省略意图时弹出输入框；需要 `agent.handler` 与 `obs-cli note.get` |
| `:[range]ObsidianAgentUpdate [意图]` | 可选 | 当前路径内安全更新；省略意图时弹出输入框；需要已保存 buffer、`agent.handler`、`note.get` / `note.patch` |
| `:ObsidianAgentLastResult` | 无 | 重新打开最近一次 Agent result 的 changed files 与恢复摘要 |
| `:ObsidianSetup` | 无 | 使用默认配置初始化插件（通常不需要手动调用） |

---

## Lua API

```lua
-- 笔记管理
require("miniobsidian.note").new_note(title?)         -- 快捷新建笔记（始终到 notes_subdir）
require("miniobsidian.note").new_note_here()           -- 在当前文件树目录下新建（snacks/neo-tree/nvim-tree/oil/netrw）
require("miniobsidian.note").new_note_in_dir(dir)      -- 在指定绝对路径目录下新建（dir 须在 vault 内）
require("miniobsidian.note").quick_switch()            -- 打开笔记 picker
require("miniobsidian.note").search(query?)            -- 全文搜索（可选初始搜索词）
require("miniobsidian.note").follow_or_create(stem)    -- 查找 stem 并跳转；不存在则提示创建

-- 每日笔记
require("miniobsidian.daily").open_today()             -- 打开/创建今日笔记

-- Wiki 链接
require("miniobsidian.link").follow_link_or_toggle()   -- 跳转 [[链接]] 或切换 checkbox
require("miniobsidian.link").link_at_cursor()          -- 返回光标处 [[链接]] 的笔记名（nil 表示不在链接上）

-- Checkbox
require("miniobsidian.checkbox").toggle()              -- 循环切换 checkbox 状态
require("miniobsidian.checkbox").clear()               -- 将 checkbox 还原为普通列表项

-- 模板
require("miniobsidian.template").new_template(name?)   -- 新建模板文件（无参则弹出输入框）
require("miniobsidian.template").insert()              -- 选择并插入模板

-- 图片
require("miniobsidian.image").paste_img(name?)         -- 粘贴剪贴板图片（macOS）

-- Vault 管理
require("miniobsidian.vault").pick_and_switch()        -- 弹出 vault 选择器
require("miniobsidian.vault").do_switch(entry)         -- 直接切换到指定 vault（entry = {name, path}）
require("miniobsidian.vault").list_vaults(parent)      -- 列出指定父目录下的所有有效 vault

-- 可选 CLI 高级能力
require("miniobsidian.move").move_current(target?)     -- dry-run、确认并事务化移动当前笔记
require("miniobsidian.move").audit()                   -- 打开只读 Vault JSON 快照
require("miniobsidian.handoff").handoff(mode, intent?, command_opts?) -- 构造并分发 Agent handoff
require("miniobsidian.handoff").last_request            -- 最近成功分发的 request payload
require("miniobsidian.agent_result").handle(result)     -- 处理 Agent result、diff 与冲突
require("miniobsidian.agent_result").show_last()        -- 重新打开最近结果摘要

-- 核心模块
require("miniobsidian").config                         -- 当前完整配置（含运行时 vault_path）
require("miniobsidian").active_vault_name              -- 当前活跃 vault 名称（可用于状态栏集成）
require("miniobsidian").get_all_notes(force?)          -- 获取 vault 内所有 .md 路径（带 5s 缓存）
require("miniobsidian").in_vault(path)                 -- 判断给定路径是否在当前 vault 内
require("miniobsidian").invalidate_cache()             -- 主动清空笔记路径缓存
```

---

## Wiki 链接格式

`<CR>`（`follow_link_or_toggle()`）支持以下 Obsidian Wiki 链接格式：

| 格式 | 示例 | 说明 |
|------|------|------|
| 简单链接 | `[[my-note]]` | 直接跳转到同名笔记 |
| 带显示别名 | `[[my-note\|显示文字]]` | 别名仅用于渲染显示，跳转目标仍是 `my-note` |
| 带章节锚点 | `[[my-note#章节标题]]` | 打开笔记并定位到匹配 heading |
| Block ID | `[[my-note#^block-id]]` | 打开笔记并定位到精确 block ID |
| 限定路径 | `[[folder/my-note]]` | 按 Vault 相对 Note ID 精确解析 |

**解析策略：**

1. 包含目录的目标按完整 Vault 相对 Note ID 匹配，随后尝试忽略大小写。
2. 不含目录的目标按 basename 匹配；如果存在多个同名笔记，弹出候选列表要求显式选择。
3. heading 支持重复标题生成的 `-1`、`-2` 锚点；block ID 必须精确匹配。
4. 目标不存在时可确认创建；限定路径会保留目标目录。

插件不会在重名时静默选择扫描结果中的第一项。

---

## 自动补全工作原理

只在**当前 vault 目录内**的 Markdown 文件中触发，不影响其他 Markdown 文件。

| 输入 | 触发效果 |
|------|---------|
| `[[` | 弹出 vault 内所有笔记名，支持模糊匹配；**悬停候选时显示笔记前 10 行预览** |
| `- [`、`* [`、`+ [` | 弹出当前 `checkbox_states` 配置的所有状态候选 |

**缓存与性能：** 首次补全时扫描全量笔记并建立内存缓存；插件自身写入会立即精确失效，Vault 文件监听会对外部创建、删除和重命名做 100ms 防抖失效；5 秒 TTL 继续作为跨平台兜底。文件监听和 `checktime` 不执行全 Vault 内容扫描。

### 外部修改与冲突

插件在 `FocusGained` / `BufEnter` 上以最小间隔执行原生 `checktime`，并接管 Vault 内 Markdown buffer 的 `FileChangedShell` 流程：

- 默认 `external_change_mode = "prompt"`：无论 buffer 是否修改，都先保留内存内容并提供 diff、保留、重新加载三个动作。
- `reload`：仅未修改 buffer 自动重载；有未保存内容时仍强制进入冲突流程。
- `notify`：保留 buffer 并通知，可用 `:ObsidianResolveConflict` 打开动作选择器。
- 每个已加载 Markdown buffer 都保存磁盘内容 SHA-256 基线；每次 `BufWritePre`
  会同步复核，因此即使没有发生焦点切换或 `checktime` 尚未运行，stale write
  仍会被阻止。
- 检测到冲突后，普通 `:write` 会被阻止，避免覆盖 Obsidian、同步工具或 Agent 写入的磁盘版本。

---

## 状态栏集成

切换 vault 后，当前活跃 vault 名会更新到 `require("miniobsidian").active_vault_name`，可直接用于 lualine 或其他状态栏：

```lua
-- lualine 示例
require("lualine").setup({
  sections = {
    lualine_x = {
      {
        function()
          local ok, core = pcall(require, "miniobsidian")
          if not ok then return "" end
          local name = core.active_vault_name
          return name ~= "" and ("󰠮 " .. name) or ""
        end,
      },
    },
  },
})
```

---

## 自定义事件

插件在完成初始化或切换 vault 时会触发 Neovim `User` 事件，供外部插件或用户配置响应：

| 事件 | 触发时机 | 携带数据 |
|------|---------|---------|
| `User MiniObsidianSetup` | `setup()` 完成后 | 无 |
| `User MiniObsidianVaultSwitch` | 切换 vault 后（默认不修改 cwd） | `{ name: string, path: string }` |
| `User MiniObsidianNoteOpened` | 笔记创建或 Daily Note 打开完成后 | `{ path: string, opts: table }` |
| `User MiniObsidianAgentHandoff` | Agent handoff 成功分发后 | `{ request_id: string, mode: string, path: string }` |

```lua
-- 示例：vault 切换后刷新 neo-tree 根目录
vim.api.nvim_create_autocmd("User", {
  pattern = "MiniObsidianVaultSwitch",
  callback = function(ev)
    local name = ev.data.name
    local path = ev.data.path
    -- 可在此处刷新 neo-tree、更新 lualine 等
    vim.notify("已切换到 vault: " .. name .. "\n路径: " .. path)
  end,
})
```

---

## 回调函数

插件通过两个回调将副作用（根目录切换、文件树刷新等）完全交给调用方控制，插件内部不执行任何全局副作用。

### `after_note_open`

在笔记文件成功打开后调用，适用于以下流程：

- `new_note(title, opts)` / `:ObsidianNew`
- `open_today(opts)` / `:ObsidianToday`
- `_create_note(title, dir, opts)`（内部通用创建函数）

**注意：** `quick_switch()` 和 `search()` 通过 picker 选择文件，插件无法预知文件何时打开，因此**不会自动调用 `after_note_open`**。如需在这两个流程完成后执行副作用，请在调用方注册 `BufEnter` 事件（见下方示例）。

```lua
require("miniobsidian").setup({
  -- after_note_open(path, opts)
  --   path: 打开的笔记文件绝对路径
  --   opts: 调用时传入的选项表（如 { switch_root = true }）
  after_note_open = function(path, opts)
    if opts and opts.switch_root then
      local vault_path = require("miniobsidian").config.vault_path
      -- 只切换当前 tab 的工作目录，不影响其他 tab
      pcall(vim.cmd, "tcd " .. vim.fn.fnameescape(vault_path))
      -- 刷新 snacks explorer（示例；换成你使用的文件树刷新逻辑）
      vim.notify("已切换根目录: " .. vault_path)
    end
  end,
})
```

### `on_vault_switch`

在 `vault.do_switch()` 更新运行时状态并触发 `MiniObsidianVaultSwitch` 事件后调用。除非显式启用 `change_cwd_on_switch`，插件不会修改 cwd；文件树刷新等副作用由此回调负责。

```lua
require("miniobsidian").setup({
  -- on_vault_switch(name, path)
  --   name: 新 vault 目录名
  --   path: 新 vault 绝对路径
  on_vault_switch = function(name, path)
    -- 示例：刷新 snacks explorer
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      local exps_ok, exps = pcall(snacks.picker.get, { source = "explorer" })
      if exps_ok and exps then
        for _, exp in ipairs(exps) do
          pcall(exp.set_cwd, exp, path)
          pcall(exp.find, exp, { refresh = true })
        end
      end
    end
    vim.notify("已切换到 vault: " .. name)
  end,
})
```

### 为 picker 流添加 BufEnter 回调

`quick_switch()` 和 `search()` 使用 snacks.nvim picker 异步选择文件，插件内部不知道文件何时最终打开。若希望打开任意 Vault 笔记时都切换当前 tab 的工作目录，可注册一个长期、Vault 范围受限的 `BufEnter`：

```lua
local group = vim.api.nvim_create_augroup("miniobsidian_picker_cwd", { clear = true })
vim.api.nvim_create_autocmd("BufEnter", {
  group = group,
  pattern = "*.md",
  callback = function(ev)
    local core = require("miniobsidian")
    if core.in_vault(ev.file) then
      pcall(vim.cmd, "tcd " .. vim.fn.fnameescape(core.config.vault_path))
    end
  end,
})
```

该回调只处理当前活跃 Vault 内的 Markdown 文件；取消 picker 不会留下等待触发的一次性 autocmd。

---

## 文件结构

```
lua/miniobsidian/
├── init.lua              配置、setup、笔记缓存与公共工具
├── path.lua              Vault 路径策略与符号链接逃逸防护
├── vault.lua             Vault 发现、切换与 picker
├── config_sync.lua       Obsidian 官方配置发现与同步
├── note.lua              笔记创建、picker、搜索与链接目标打开
├── wikilink.lua          Wikilink 解析、消歧及 fragment 定位
├── link.lua              光标链接检测与 checkbox 复合动作
├── daily.lua             Daily Note 解析与创建
├── datetime.lua          Moment 子集转换和模板日期渲染
├── template.lua          模板创建、选择与变量替换
├── checkbox.lua          Checkbox 状态循环与清除
├── completion.lua        blink.cmp 补全与异步预览
├── image.lua             macOS 剪贴板图片粘贴
├── external_changes.lua  外部修改检测、SHA-256 写入保护与 diff
├── cli.lua               obs-cli capability 与协议 Adapter
├── move.lua              dry-run + revision/plan_hash 安全移动
├── handoff.lua           有界 Agent handoff payload
├── agent_result.lua      Agent 结果、diff 与三方冲突视图
├── health.lua            :checkhealth 实现
└── scripts/
    └── paste_image.js     macOS JXA 图片保存脚本
plugin/
└── miniobsidian.lua      用户命令与 autocmd 注册
doc/
├── miniobsidian.txt      English Vim help
└── miniobsidian.zh.txt   中文 Vim help
```

---

## 鸣谢

- [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim) by [@epwalsh](https://github.com/epwalsh) —— 本插件的灵感来源。如需功能完整、久经考验的 Obsidian Neovim 客户端，推荐使用该插件。
- [snacks.nvim](https://github.com/folke/snacks.nvim) by [@folke](https://github.com/folke) —— 提供 Picker UI 支持。
- [blink.cmp](https://github.com/Saghen/blink.cmp) by [@Saghen](https://github.com/Saghen) —— 提供自动补全集成能力。

## License

MIT © [andy-neoaira](https://github.com/andy-neoaira)
