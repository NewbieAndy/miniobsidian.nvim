# 协作约定

- 所有对话尽量使用中文。
- 修改前检查工作区状态，保留已有改动；未经要求不要提交或推送。
- 修复问题时补充可复现的回归测试，说明行为变化、验证结果和未实测的范围。

# 项目结构

- 本项目是独立的 Neovim 笔记插件，最低支持 Neovim 0.10.4。
- `plugin/miniobsidian.lua` 注册命令和自动命令，功能实现在 `lua/miniobsidian/`。
- `note.lua` 保持公共 API，创建、移动、选择器等实现放在相应模块。
- `path.lua` 负责 Vault 路径边界与真实路径解析，`fs.lua` 负责共享文件 I/O。
- `markdown.lua` 提供代码、注释和 Wikilink 的共享扫描逻辑；`markdown_link.lua`
  负责 Markdown 路径编码与移动后的相对路径重算。不要在调用方重复实现扫描器。

# 数据与行为约定

- 测试使用临时 Vault，不读取或改写个人 Vault，不操作真实剪贴板；模拟外部依赖后恢复原值。
- 内容路径必须通过 Vault 边界检查，禁止隐藏目录或符号链接逃逸；笔记身份按真实路径去重。
- 创建文件不得覆盖已有目标；移动和引用更新应保留失败回滚，覆盖已写入部分的恢复测试。
- 保留未保存的用户编辑、代码示例、注释、自定义标题和原本存在歧义的链接。
- 引用改写以操作前的真实目标为准，同时检查新名称是否影响其他笔记的短链接。
- 按完整 Unicode 字符处理笔记标题；文件名、YAML 字符串、Markdown 标签和 URL 路径
  使用各自的校验或转义规则，不能混用。
- 保持可选依赖可选，不把 Snacks、blink.cmp、ripgrep 或 macOS 剪贴板能力变成基础功能的硬依赖。
- 不引入跨客户端锁、外部文件监听或事务协调，除非任务明确要求调整产品边界。

# 验证与文档

- Lua 格式遵循 `stylua.toml`，静态检查遵循 `selene.toml`。
- 代码修改完成后运行 `make ci`，它包含格式、静态检查、文档契约、模块测试归属和测试。
- Plenary 路径不同时使用 `make ci PLENARY_DIR=/absolute/path/to/plenary.nvim`。
- 新增模块时更新 `scripts/check-module-tests.sh` 中的测试归属，并提供实际行为测试。
- 涉及写入的修复应覆盖失败路径；涉及移动的修复应检查磁盘内容、已加载 buffer 和引用目标。
- 用户可见行为或 API 变化应同步四份文档：`README.md`（英文）、`README.en.md`（中文）、
  `doc/miniobsidian.txt`（英文）、`doc/miniobsidian.zh.txt`（中文）。不要因文件命名反直觉而直接互换 README。
- 最后运行 `git diff --check`，报告实际执行的检查；未实测的平台或依赖集成不要声称已验证。
