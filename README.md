# miniobsidian.nvim

轻量、独立的 Obsidian 工作流 Neovim 插件。中文 · [English](README.en.md)

`miniobsidian.nvim` 专注 Neovim 内的笔记体验：发现和切换 Vault、创建与搜索
笔记、Wikilink、模板、Daily Note、Checkbox 和图片粘贴。插件不集成外部
CLI 或 Agent，也不承担多个客户端之间的写入协调。

## 功能

- 从 Obsidian 官方配置自动发现多个 Vault，或扫描指定 Vault 父目录
- 在默认目录或文件树当前目录创建笔记，支持自定义 Note ID
- 通过 `snacks.nvim` 快速切换笔记和全文搜索
- 跳转和创建 Wikilink，支持 alias、heading、block ID、限定路径和同名消歧
- 通过 `blink.cmp` 补全笔记目标和 Checkbox 状态，并预览笔记内容
- Checkbox 状态循环、普通列表升级和 Checkbox 清除
- 递归模板选择、模板创建和 Obsidian 风格日期变量
- 同步 Obsidian 新笔记目录及 Daily Notes 目录、格式和模板
- macOS 剪贴板图片粘贴；同名目标自动递增且不会覆盖已有图片
- Vault 路径边界、符号链接逃逸、隐藏目录和跨平台文件名检查
- 笔记、模板、Daily Note 和图片均使用 no-replace 语义

## 产品边界

Markdown Vault 是内容来源。Obsidian、Neovim、同步软件和其他工具都可能直接
修改它。本插件不实现 revision、乐观锁、外部修改监听、三方合并或跨客户端
事务；外部文件变化和写入冲突沿用 Neovim 自身行为，备份与恢复由 Git、同步
历史或用户工作流负责。

插件仍保证自身操作的基本正确性：所有目标必须位于当前 Vault 内；非法或失效
Vault 会被拒绝；从 Obsidian 同步的配置会在应用前验证；创建操作不会替换已有
目标；I/O 失败会明确提示。

## 要求

- Neovim >= 0.10.4
- `snacks.nvim`：快速切换和全文搜索，可选
- `blink.cmp`：Wikilink 与 Checkbox 补全，可选
- `ripgrep`：全文搜索，可选
- `osascript`：图片粘贴，仅 macOS

没有安装可选依赖时，Vault、笔记、模板、Daily Note、Wikilink 跳转和 Checkbox
等基础功能仍可使用。

## 安装

lazy.nvim 示例：

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
})
```

## 配置参考

| 配置项 | 默认值 | 说明 |
|---|---|---|
| `vaults_parent` | `""` | Vault 父目录；支持 `~` 和环境变量展开。为空时可自动发现 |
| `default_vault` | `""` | 初始 Vault 名；为空或找不到时使用发现列表的第一个 |
| `auto_discover` | `true` | `vaults_parent` 为空时读取 Obsidian 官方配置 |
| `sync_obsidian_config` | `true` | 读取当前 Vault 的官方配置；只读，不修改 `.obsidian` |
| `notes_subdir` | `"Notes"` | 新笔记目录，Vault 相对路径；空字符串表示 Vault 根目录 |
| `dailies_folder` | `""` | Daily Note 目录，Vault 相对路径 |
| `daily_template` | `""` | Daily Note 模板的 Vault 相对 Note ID，可省略 `.md` |
| `daily_default_content` | `""` | 没有模板时写入新 Daily Note 的内容 |
| `templates_folder` | `"Templates"` | 模板目录，Vault 相对路径 |
| `attachments_folder` | `"Assets"` | 图片附件目录，Vault 相对路径 |
| `daily_date_format` | `"%Y-%m-%d"` | Lua `os.date` 格式，用于 Daily 文件名和新笔记日期 |
| `picker_scope` | `"notes"` | `"notes"` 只搜索 `notes_subdir`；`"vault"` 搜索整个 Vault |
| `change_cwd_on_switch` | `false` | 切换 Vault 时是否执行 tab-local `:tcd` |
| `checkbox_states` | `{ " ", "x" }` | Checkbox 循环及补全顺序 |
| `note_id_func` | 内置 CJK slug | 将标题转换为新笔记文件名，不含 `.md` |
| `on_vault_switch` | `nil` | `function(name, path)`，Vault 成功切换后调用 |
| `after_note_open` | `nil` | `function(path, opts)`，插件直接打开笔记后调用 |

`vault_path` 是运行时内部字段，由 `setup()` 和 Vault 切换维护，不应手动配置。

默认 `note_id_func` 保留 ASCII 字母数字和中日韩文字，删除其他标点，将连续空白
替换为 `-`，并将 ASCII 转为小写。例如：

- `Hello World` → `hello-world`
- `我的笔记 2026` → `我的笔记-2026`
- `A & B!` → `a-b`

如需自定义，应明确传入自己的函数：

```lua
require("miniobsidian").setup({
  note_id_func = function(title)
    return os.date("%Y%m%d%H%M%S") .. "-" .. title:lower():gsub("%s+", "-")
  end,
  checkbox_states = { " ", "/", "x", "-" },
})
```

路径配置必须是安全的 Vault 相对路径，不接受 `..`、绝对路径、隐藏目录段、NUL、
Windows ADS、保留设备名或以点/空格结尾的路径段。

### Obsidian 配置同步

当 `sync_obsidian_config=true` 时只读：

- `.obsidian/app.json`
  - `newFileLocation` / `newFileFolderPath` → `notes_subdir`
- `.obsidian/daily-notes.json`
  - `folder` → `dailies_folder`
  - `format` → `daily_date_format`
  - `template` → `daily_template`

优先级为：用户显式配置 > 当前 Vault 的 Obsidian 配置 > 插件默认值。每次切换
Vault 都会从这个顺序重新构造同步字段，不会继承上一个 Vault 的目录。同步结果
整体校验通过后才会切换；非法配置会保留原活跃 Vault。

`setup(opts)` 成功返回 `true`；配置非法、没有有效 Vault 或同步结果非法时返回
`false, errors`，且不会触发 `MiniObsidianSetup`。

## blink.cmp 补全

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

补全仅在当前 buffer 是 Vault 内的 Markdown 文件时启用。输入 `[[` 会列出笔记
目标；同名笔记插入 Vault 相对限定路径，候选预览读取文件前 10 行。输入 `- [`、
`* [` 或 `+ [` 会按 `checkbox_states` 提供状态。

## 命令

| 命令 | 参数 | 说明 |
|---|---|---|
| `:ObsidianNew[!] [标题]` | 标题可选 | 在 `notes_subdir` 创建或打开笔记；`!` 传递 `switch_root=true` |
| `:ObsidianNewHere` | 无 | 在支持的文件树当前目录创建笔记；无法识别时回退到 `notes_subdir` |
| `:ObsidianSwitchVault` | 无 | 选择并切换活跃 Vault |
| `:ObsidianSwitch` | 无 | 使用 snacks 模糊查找 Markdown 笔记 |
| `:ObsidianSearch [关键词]` | 关键词可选 | 使用 snacks + ripgrep 全文搜索 Markdown |
| `:ObsidianTemplate` | 无 | 递归选择模板，渲染后插入光标下一行 |
| `:ObsidianNewTemplate [名称]` | 名称可选 | 创建或打开模板，不覆盖已有模板 |
| `:ObsidianPasteImg [名称]` | 名称可选 | macOS 粘贴图片并插入相对 Markdown 链接 |
| `:ObsidianToday[!]` | 无 | 打开或创建今日笔记；`!` 传递 `switch_root=true` |
| `:ObsidianSetup` | 无 | 使用默认配置调用 `setup()`，通常只用于测试或无插件管理器环境 |

`ObsidianNewHere` 支持 snacks explorer、neo-tree、nvim-tree、oil.nvim 和 netrw。
检测到 Vault 外目录时会中止，不会静默回退到 Vault。

## Wikilink

导航支持：

| 形式 | 行为 |
|---|---|
| `[[Note]]` | 按 basename 查找唯一笔记 |
| `[[Folder/Note]]` | 按 Vault 相对 Note ID 精确查找 |
| `[[Note\|Alias]]` | 保留 alias，按 `Note` 跳转 |
| `[[Note#Heading]]` | 打开笔记并定位 heading |
| `[[Note#^block-id]]` | 打开笔记并定位行末 block ID |

同 basename 对应多篇笔记时会要求选择，不会任意打开第一篇。不存在的限定路径
目标可在确认后按原目录和文件名创建。当前不支持当前文档内部形式 `[[#Heading]]`；
blink 补全只提供笔记目标，不补全 alias、heading 或 block ID。

可将跟随链接和 Checkbox 切换绑定到同一个键：

```lua
vim.keymap.set("n", "<CR>", function()
  require("miniobsidian.link").follow_link_or_toggle()
end)
```

## Checkbox

`checkbox.toggle()` 按 `checkbox_states` 循环状态；普通 `- item`、`* item`、
`+ item` 会升级成第一个状态。`checkbox.clear()` 将 Checkbox 恢复为普通列表项。

```lua
vim.keymap.set("n", "<leader>nt", function() require("miniobsidian.checkbox").toggle() end)
vim.keymap.set("n", "<leader>nc", function() require("miniobsidian.checkbox").clear() end)
```

## 模板和 Daily Note

模板变量大小写不敏感：

| 变量 | 说明 |
|---|---|
| `{{date}}` | 按 `daily_date_format` 输出日期 |
| `{{time}}` | 当前时间 `HH:MM` |
| `{{title}}` / `{{filename}}` | 当前文件名，不含扩展名 |
| `{{yesterday}}` / `{{tomorrow}}` | 本地日历的前一天/后一天，正确跨越 DST |
| `{{date:FORMAT}}` | 使用 Moment 风格子集输出自定义日期 |

`FORMAT` 支持 `YYYY`、`YY`、`MMMM`、`MMM`、`MM`、`DD`、`dddd`、`ddd`、
`HH`、`hh`、`mm`、`ss`、`A`、`a`，以及 `[literal]` 字面量。不支持的 token
会导致本次渲染失败；未知普通变量保持原文并发出警告。

Daily Note 的目标为 `dailies_folder/os.date(daily_date_format).md`。文件已存在时
直接打开，不再读取模板；文件不存在时优先渲染 `daily_template`，没有模板则写入
`daily_default_content`。缺失或同名歧义的模板会中止创建。

## 图片粘贴

仅 macOS 支持。Finder 复制的图片保留 PNG、JPEG、GIF、WEBP、HEIC、HEIF、
TIFF、BMP 或 SVG 格式；截图和浏览器图片转换为 PNG/JPG/GIF。图片保存到
`attachments_folder`，链接使用当前笔记到图片的相对路径。

如果目标名已经被任一支持格式占用，会自动选择 `name-1`、`name-2`。图片先写入
同目录临时文件，再以排他方式发布，最终目标不会被替换。

## 回调与事件

```lua
require("miniobsidian").setup({
  after_note_open = function(path, opts)
    if opts.switch_root then
      vim.cmd("tcd " .. vim.fn.fnameescape(vim.fn.fnamemodify(path, ":h")))
    end
  end,
  on_vault_switch = function(name, path)
    vim.notify(("Vault: %s (%s)"):format(name, path))
  end,
})
```

- `after_note_open(path, opts)`：由 `new_note()`（包括打开同 ID 已有笔记）、
  跟随缺失链接后的创建和 Daily Note 流程调用。已有 Wikilink 的普通跳转、模板、
  quick switch 和 search 不调用它。`opts.switch_root` 来自命令的 `!`。回调前触发
  `MiniObsidianNoteOpened`。
- `on_vault_switch(name, path)`：Vault 配置成功应用、缓存失效和
  `MiniObsidianVaultSwitch` 事件触发后调用。

`quick_switch()` 和 `search()` 由 snacks 自己打开文件，因此不会调用
`after_note_open`。需要统一处理 picker 打开的笔记时，请使用 `BufEnter`：

```lua
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*.md",
  callback = function(ev)
    local core = require("miniobsidian")
    local path = vim.api.nvim_buf_get_name(ev.buf)
    if core.in_vault(path) then
      -- 在这里刷新文件树、状态栏或项目根目录
    end
  end,
})
```

插件事件：

| 事件 | data | 时机 |
|---|---|---|
| `User MiniObsidianSetup` | 无 | `setup()` 成功完成后 |
| `User MiniObsidianVaultSwitch` | `{ name, path }` | Vault 成功切换后 |
| `User MiniObsidianNoteOpened` | `{ path, opts }` | 插件直接打开笔记后 |

## Lua API

常用公共 API：

```lua
local core = require("miniobsidian")
core.setup(opts)                 -- true，或 false, errors
core.default_config()            -- 返回新的默认配置表
core.validate_config(config)     -- 返回错误字符串列表
core.get_all_notes(force)        -- Vault 内安全的 Markdown 绝对路径列表
core.invalidate_cache()
core.update_note_cache(path)     -- 插件写入后的单路径增量更新
core.in_vault(path)

local note = require("miniobsidian.note")
note.new_note(title?, opts?)
note.new_note_here()
note.new_note_in_dir(absolute_dir)
note.quick_switch()
note.search(query?)
note.follow_or_create(wikilink_or_parsed)

require("miniobsidian.vault").pick_and_switch()
require("miniobsidian.vault").do_switch({ name = name, path = path })
require("miniobsidian.daily").open_today(opts?)
require("miniobsidian.daily").resolve_today(opts?)
require("miniobsidian.template").insert()
require("miniobsidian.template").new_template(name?)
require("miniobsidian.link").follow_link_or_toggle()
require("miniobsidian.checkbox").toggle()
require("miniobsidian.checkbox").clear()
require("miniobsidian.image").paste_img(name?)
```

以下主要是集成或内部辅助接口，可能比上面的用户工作流 API 更容易变化：
`wikilink.parse/resolve/locate_fragment`、`config_sync.*`、`path.*`、`fs.*`、
`image.resolve_for_snacks`、`completion.new`。

用户回调异常会被隔离并产生 WARN 通知，不会中断笔记打开或 Vault 切换流程。

## 常用按键示例

```lua
vim.keymap.set("n", "<leader>nn", function() require("miniobsidian.note").new_note() end)
vim.keymap.set("n", "<leader>no", function() require("miniobsidian.note").quick_switch() end)
vim.keymap.set("n", "<leader>ns", function() require("miniobsidian.note").search() end)
vim.keymap.set("n", "<leader>nd", function() require("miniobsidian.daily").open_today() end)
vim.keymap.set("n", "<leader>np", function() require("miniobsidian.image").paste_img() end)
```

插件不预设任何按键。

## 健康检查与测试

```vim
:checkhealth miniobsidian
:help miniobsidian
:help miniobsidian-zh
```

```sh
make ci
```

健康检查会验证 Neovim 版本、可选依赖、配置合法性、Vault 来源和当前活跃 Vault。

## License

MIT
