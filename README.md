# miniobsidian.nvim

轻量、独立的 Obsidian 工作流 Neovim 插件。

`miniobsidian.nvim` 只负责 Neovim 内的笔记体验：发现 Vault、新建和查找笔记、
Wikilink、模板、Daily Note、Checkbox 与图片粘贴。它不集成外部 CLI、Agent
框架，也不承担多个客户端之间的写入协调。

## 功能

- 从 Obsidian 官方配置自动发现多个 Vault，也可手动配置 Vault 父目录
- 新建笔记，支持文件树当前目录与自定义 Note ID
- 通过 `snacks.nvim` 快速切换笔记和全文搜索
- 跳转、创建和补全 `[[Wikilink]]`，支持 alias、heading、block ID 与重名提示
- Checkbox 状态循环与 blink.cmp 补全
- 递归模板选择和 Obsidian 风格日期变量
- 同步 Obsidian Daily Notes 目录、日期格式和模板
- macOS 剪贴板图片粘贴
- Vault 路径边界、符号链接逃逸和跨平台文件名检查
- 新建文件使用 no-replace 语义，已有笔记不会被截断

## 产品边界

Markdown Vault 是内容来源，Obsidian、Neovim、同步软件和其他工具都可能直接修改它。
本插件不实现 revision、乐观锁、外部修改监听、三方合并或跨客户端事务；文件变化与
写入冲突沿用 Neovim 自身行为，备份和恢复由 Git、同步历史或用户工作流负责。

插件仍保证自身操作的基本正确性：路径必须位于当前 Vault 内，新建笔记、模板和
Daily Note 不会覆盖已存在目标，I/O 失败会明确提示。

## 要求

- Neovim >= 0.10.4
- `snacks.nvim`：快速切换和全文搜索，可选
- `blink.cmp`：Wikilink 与 Checkbox 补全，可选
- `ripgrep`：全文搜索，可选
- `osascript`：图片粘贴，仅 macOS

## 安装

```lua
{
  "andy-neoaira/miniobsidian.nvim",
  ft = "markdown",
  cmd = {
    "ObsidianNew",
    "ObsidianNewHere",
    "ObsidianSwitchVault",
    "ObsidianSwitch",
    "ObsidianSearch",
    "ObsidianTemplate",
    "ObsidianNewTemplate",
    "ObsidianPasteImg",
    "ObsidianToday",
    "ObsidianSetup",
  },
  config = function()
    require("miniobsidian").setup()
  end,
}
```

默认从 Obsidian 官方 `obsidian.json` 自动发现 Vault。手动配置示例：

```lua
require("miniobsidian").setup({
  vaults_parent = "~/Documents/Obsidian",
  default_vault = "Personal",
  auto_discover = false,
  notes_subdir = "Notes",
  templates_folder = "Templates",
  attachments_folder = "Assets",
  dailies_folder = "Dailies",
  daily_date_format = "%Y-%m-%d",
  checkbox_states = { " ", "/", "x", "-" },
})
```

可选的 blink.cmp source：

```lua
{
  "saghen/blink.cmp",
  opts = function(_, opts)
    opts.sources = opts.sources or {}
    opts.sources.default = vim.list_extend(opts.sources.default or {}, { "miniobsidian" })
    opts.sources.providers = vim.tbl_deep_extend("force", opts.sources.providers or {}, {
      miniobsidian = {
        name = "MiniObsidian",
        module = "miniobsidian.completion",
        score_offset = 50,
      },
    })
    return opts
  end,
}
```

## 配置

```lua
require("miniobsidian").setup({
  vaults_parent = "",
  default_vault = "",
  auto_discover = true,
  sync_obsidian_config = true,
  notes_subdir = "Notes",
  dailies_folder = "",
  daily_template = "",
  daily_default_content = "",
  templates_folder = "Templates",
  attachments_folder = "Assets",
  daily_date_format = "%Y-%m-%d",
  picker_scope = "notes", -- "notes" 或 "vault"
  change_cwd_on_switch = false,
  checkbox_states = { " ", "x" },
  note_id_func = function(title)
    return title:lower():gsub("%s+", "-")
  end,
  on_vault_switch = nil,
  after_note_open = nil,
})
```

当 `sync_obsidian_config=true` 时，插件只读以下官方配置：

- `.obsidian/app.json`：新笔记目录
- `.obsidian/daily-notes.json`：Daily Note 目录、格式和模板

用户显式配置始终优先。

## 命令

| 命令 | 说明 |
|---|---|
| `:ObsidianNew[!] [标题]` | 在默认笔记目录创建或打开笔记 |
| `:ObsidianNewHere` | 在当前文件树目录创建笔记 |
| `:ObsidianSwitchVault` | 切换活跃 Vault |
| `:ObsidianSwitch` | 快速切换笔记 |
| `:ObsidianSearch [关键词]` | 全文搜索 |
| `:ObsidianTemplate` | 插入模板 |
| `:ObsidianNewTemplate [名称]` | 创建或打开模板 |
| `:ObsidianPasteImg [名称]` | 粘贴剪贴板图片（macOS） |
| `:ObsidianToday[!]` | 打开或创建今日笔记 |
| `:ObsidianSetup` | 使用默认配置初始化 |

插件不预设快捷键。示例：

```lua
vim.keymap.set("n", "<leader>nn", function() require("miniobsidian.note").new_note() end)
vim.keymap.set("n", "<leader>no", function() require("miniobsidian.note").quick_switch() end)
vim.keymap.set("n", "<leader>nd", function() require("miniobsidian.daily").open_today() end)
vim.keymap.set("n", "<CR>", function() require("miniobsidian.link").follow_link_or_toggle() end)
```

## 模板变量

支持 `{{date}}`、`{{time}}`、`{{title}}`、`{{filename}}`、`{{yesterday}}`、
`{{tomorrow}}` 和 `{{date:YYYY/MM/DD}}`。变量大小写不敏感，未知变量保留并提示。

## 健康检查与测试

```vim
:checkhealth miniobsidian
:help miniobsidian
:help miniobsidian-zh
```

```sh
make ci
```

## License

MIT
