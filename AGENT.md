# miniobsidian.nvim Agent 协作指南

本文件适用于整个仓库。修改代码前先阅读相关模块、对应测试，以及公开行为涉及的中英文文档。默认使用中文沟通；代码标识符、公开 API 名称和既有英文注释保持原样。

## 项目定位

`miniobsidian.nvim` 是面向 Neovim >= 0.10.4 的轻量 Obsidian 工作流插件，提供 Vault 发现与切换、笔记、Wikilink、模板、Daily Note、Checkbox、补全和 macOS 图片粘贴。

项目刻意不提供外部 CLI、Agent 集成、跨客户端事务、revision、三方合并或外部文件监听。不要重新引入以下已移除概念：

- `miniobsidian.cli`
- `external_change_mode`
- `watch_external_changes`
- `miniobsidian.agent_result`
- `ObsidianMove`
- `ObsidianAudit`

## 目录与模块职责

- `plugin/miniobsidian.lua`：插件入口；只注册用户命令和 setup 后的 autocmd，依赖通过回调延迟加载。插件不预设按键。
- `lua/miniobsidian/init.lua`：配置默认值、配置验证、活跃 Vault 状态、笔记缓存、公共核心 API、回调和 `MiniObsidianSetup`/`MiniObsidianNoteOpened` 事件。
- `lua/miniobsidian/vault.lua`：Vault 扫描、选择、运行时切换及 `MiniObsidianVaultSwitch`。
- `lua/miniobsidian/config_sync.lua`：只读 Obsidian 官方配置；负责自动发现和 Vault 配置同步。
- `lua/miniobsidian/note.lua`：稳定的笔记公共门面。创建逻辑在 `note_create.lua`，picker 逻辑在 `note_picker.lua`；调用方优先依赖门面。
- `lua/miniobsidian/path.lua`：所有 Vault 路径验证、归一化、符号链接边界与跨平台文件名策略。
- `lua/miniobsidian/fs.lua`：共享文件 I/O 与 no-replace 发布原语。
- `lua/miniobsidian/wikilink.lua` / `link.lua`：Wikilink 解析、解析目标、片段定位和光标动作。
- `lua/miniobsidian/datetime.lua` / `template.lua` / `daily.lua`：日期格式转换、模板渲染和 Daily Note 规划/创建。
- `lua/miniobsidian/completion.lua`：blink.cmp source；只在活跃 Vault 内的 Markdown buffer 启用。
- `lua/miniobsidian/explorer.lua`：snacks explorer、neo-tree、nvim-tree、oil.nvim、netrw 适配。
- `lua/miniobsidian/image.lua`：macOS 图片粘贴；JXA 实现在 `lua/miniobsidian/scripts/paste_image.js`。
- `lua/miniobsidian/checkbox.lua`：Checkbox 循环、普通列表升级和清除。
- `lua/miniobsidian/health.lua` 与 `lua/health/miniobsidian.lua`：`:checkhealth miniobsidian`。
- `tests/`：Plenary/Busted 测试；`tests/helpers.lua` 创建临时 Vault，禁止测试读写个人 Vault。

## 必须保持的行为契约

### Vault 与路径安全

- 所有由用户输入或配置派生的内容目标路径必须经过 `miniobsidian.path`。不要手工拼接后直接读写。
- Vault 相对路径必须拒绝绝对路径、`..`、隐藏目录段、NUL、Windows ADS、保留设备名及尾随点/空格。
- 对已存在路径和待创建路径都要验证符号链接解析结果，禁止逃逸活跃 Vault。
- 仅在明确接受绝对路径的内部接口中使用 `allow_absolute = true`，并仍需验证路径位于 Vault 内。
- `vault_path` 是运行时内部字段，不是用户配置项。

### 写入与缓存

- 新笔记、模板、Daily Note 和图片必须保持 no-replace 语义。优先使用 `fs.create_exclusive()` 或 `fs.link_exclusive()`；不得用会静默覆盖目标的普通写入替代。
- 失败不得留下半成品；临时文件必须清理。
- 插件成功创建或删除单篇笔记后使用 `update_note_cache(path)`；无法精确更新或切换 Vault 时使用 `invalidate_cache()`。
- 缓存只包含活跃 Vault 内非隐藏目录中的 Markdown 文件。

### 配置与 Vault 切换

- 默认配置必须由 `new_default_config()`/`default_config()` 产生，避免跨 `setup()` 调用共享可变表。
- 用户显式配置优先于 Obsidian 同步配置，同步配置优先于插件默认值。
- 切换 Vault 时重新构造可同步字段，禁止沿用上一个 Vault 的目录设置。
- 运行时 Vault 切换应先验证候选配置，再原子提交；失败时保留原活跃 Vault。
- `change_cwd_on_switch` 只能执行 tab-local `:tcd`，不能全局改变其他 tab 或项目的 cwd。

### 可选依赖与异步边界

- `snacks.nvim`、`blink.cmp`、`ripgrep` 都是可选依赖。除明确依赖它们的功能外，核心工作流必须继续可用。
- Vault 和模板选择优先 snacks，缺失时回退 `vim.ui.select`。
- 可选 Lua 模块使用 `pcall(require, ...)`，不要在核心模块顶层强制加载。
- libuv 回调、picker 回调或可能处于 textlock/fast-event 的路径，在调用 Neovim API 前使用 `vim.schedule()`、`vim.schedule_wrap()` 或等价安全边界。

### 公开事件与回调

- `MiniObsidianSetup`：`setup()` 成功后触发。
- `MiniObsidianVaultSwitch`：运行时 Vault 成功切换后触发，`data = { name, path }`。
- `MiniObsidianNoteOpened`：插件直接打开笔记后触发，`data = { path, opts }`。
- 用户配置回调统一通过 `core.run_callback()` 隔离异常；回调失败应 WARN，但不能破坏已成功的插件流程。
- 修改事件顺序、回调参数或命令 bang 语义属于公开行为变更，必须同步测试和四份正式文档。

## 实现约定

- Lua 使用 2 空格缩进，行宽 120，遵循 `stylua.toml`。
- 兼容 Neovim 内置 LuaJIT；不要假设独立 Lua 解释器行为与 Neovim 完全一致。
- 优先使用 `vim.uv or vim.loop`，除非目标模块明确要求最低版本已有的 API。
- 用户可见错误应通过 `core.notify()` 或带 `[miniobsidian]` 前缀的 `vim.notify()`，并选择合适的 INFO/WARN/ERROR 等级。
- 文件路径传给 Ex 命令时必须使用 `vim.fn.fnameescape()`；外部进程参数使用 argv 列表，不经 shell 拼接。
- 保持 `note.lua` 等公共门面的兼容性。拆分实现时先保留已有入口，再迁移内部代码。
- 不要添加全局按键映射、全局 cwd 副作用或与当前工作流无关的自动命令。

## 测试要求

每次改动至少运行与改动对应的测试；提交前运行完整 CI：

```sh
make ci
```

常用分层命令：

```sh
make format-check
make lint
make docs-check
make module-test-check
make test
```

环境可通过以下变量覆盖：

```sh
make ci NVIM=/path/to/nvim PLENARY_DIR=/path/to/plenary.nvim
```

新增或拆分 `lua/miniobsidian/*.lua` 模块时：

1. 在 `tests/` 中增加或指定对应测试文件。
2. 更新 `scripts/check-module-tests.sh` 的模块归属表。
3. 使用 `tests/helpers.lua` 创建临时 Vault，并在测试结束时清理。
4. 覆盖成功、失败、路径逃逸、已有目标和可选依赖缺失等相关边界。

测试不得依赖用户主目录中的真实 Obsidian Vault、真实剪贴板内容或已登录的外部服务。

## 文档同步要求

正式文档共有四份：

- `README.md`
- `README.en.md`
- `doc/miniobsidian.txt`
- `doc/miniobsidian.zh.txt`

新增或修改以下内容时必须同步四份文档：配置项及默认值、用户命令、公开事件、公共 Lua API、依赖要求、平台限制和用户可见行为。

- Vim help 使用合法 help tag，并保持中英文 tag 不冲突。
- 不要手工维护 `doc/tags`；运行 `make docs-check` 由 `:helptags` 校验生成。
- Lua 代码块必须是合法 Lua；可选参数用注释或实际调用示例说明，不要写 `opts?` 之类不可执行语法。
- 以源码和测试为事实来源。文档与实现冲突时，先确认预期契约，再同步实现、测试与文档。

## 提交前检查

- 只修改当前任务需要的文件，不覆盖或清理用户的无关改动。
- 检查 `git diff --check`。
- 确认新增文件已被测试/文档契约覆盖，且没有意外加入 `nvim.log`、临时 Vault 或生成文件。
- 报告实际执行的验证命令；未运行的检查必须明确说明原因。
