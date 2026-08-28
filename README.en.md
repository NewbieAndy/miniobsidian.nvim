# miniobsidian.nvim

A lightweight, standalone Obsidian workflow plugin for Neovim. English · [中文](README.md)

`miniobsidian.nvim` focuses on the editor experience: Vault discovery and switching,
note creation and search, Wikilinks, templates, Daily Notes, checkboxes, and file
paste. It has no external CLI or Agent integration and does not coordinate writes
across clients.

> **Inspired by** [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim) — a full-featured Obsidian client for Neovim. `miniobsidian.nvim` takes a lighter approach: no Telescope dependency, a lightweight event model, just the features you actually use every day. If you need a more complete, battle-tested solution, use that instead.

## Features

- Discover Vaults from Obsidian configuration or a configured parent directory
- Create notes in the default folder or the current file-tree directory
- Switch and search Markdown notes through `snacks.nvim`
- Navigate and create Wikilinks with aliases, headings, block IDs, qualified paths,
  and duplicate-name disambiguation
- Scan backlinks to the current note and jump to exact reference lines without LSP
- Move or rename notes while updating Vault Wikilinks from their pre-move resolution
- Complete note targets and checkbox states through `blink.cmp`, with note previews
- Cycle and clear checkboxes, including upgrading plain list items
- Select recursive templates and render Obsidian-style date variables
- Synchronize Obsidian's new-note and Daily Notes settings
- Paste macOS clipboard files or images with collision-safe incrementing names
- Enforce Vault boundaries, symlink containment, hidden-directory policy, and
  cross-platform filename rules
- Use no-replace publication for notes, templates, Daily Notes, and files

## Scope

The Markdown Vault is the content source. Obsidian, Neovim, sync software, and other
tools may all modify it. This plugin deliberately does not implement revisions,
optimistic locking, external-change watchers, three-way merge UI, or cross-client
transactions. Neovim handles external changes and write conflicts; recovery belongs
to Git, sync history, or the user's workflow.

The plugin still validates every target against the active Vault, rejects stale Vault
entries and unsafe synchronized settings, never replaces an existing create target,
and reports I/O failures.

## Requirements

- Neovim >= 0.10.4
- `snacks.nvim` for note switching and search, optional
- `blink.cmp` for Wikilink and checkbox completion, optional
- `ripgrep` for full-text search, optional
- `osascript` for clipboard file/image paste, macOS only

Core Vault, note, template, Daily Note, link navigation, and checkbox workflows remain
available without optional dependencies. Vault and template selectors fall back to
`vim.ui.select`. Without `snacks.nvim`, only `ObsidianSwitch`, `ObsidianSearch`, and
`ObsidianBacklinks`
are unavailable; without ripgrep, only full-text search is unavailable.

## Installation

lazy.nvim example:

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
    "ObsidianBacklinks",
    "ObsidianMove",
    "ObsidianRename",
    "ObsidianTemplate",
    "ObsidianNewTemplate",
    "ObsidianPasteFile",
    "ObsidianToday",
    "ObsidianSetup",
  },
  config = function()
    require("miniobsidian").setup()
  end,
}
```

Zero-config setup discovers Vaults from Obsidian's official `obsidian.json`, ignoring
missing entries and paths without `.obsidian/`. With manual discovery, only direct
children of `vaults_parent` that contain `.obsidian/` are treated as Vaults:

```lua
require("miniobsidian").setup({
  vaults_parent = "~/Documents/Obsidian",
  default_vault = "Personal",
  auto_discover = false,
})
```

## Configuration reference

| Option | Default | Description |
|---|---|---|
| `vaults_parent` | `""` | Parent directory containing Vaults; expands `~` and environment variables |
| `default_vault` | `""` | Initial Vault name; falls back to the first result; an Obsidian-marked open Vault is prioritized during automatic discovery |
| `auto_discover` | `true` | Read official Obsidian configuration when no parent is set |
| `sync_obsidian_config` | `true` | Read settings from the active Vault; never writes `.obsidian` |
| `notes_subdir` | `"Notes"` | Vault-relative new-note folder; empty means Vault root |
| `dailies_folder` | `""` | Vault-relative Daily Note folder |
| `daily_template` | `""` | Vault-relative Daily template Note ID; `.md` is optional |
| `daily_default_content` | `""` | Initial Daily Note content when no template is configured |
| `templates_folder` | `"Templates"` | Vault-relative template folder |
| `attachments_folder` | `"Assets"` | Vault-relative image folder |
| `daily_date_format` | `"%Y-%m-%d"` | Lua `os.date` format for Daily filenames and note dates |
| `picker_scope` | `"notes"` | `"notes"` searches `notes_subdir`; `"vault"` searches the full Vault |
| `change_cwd_on_switch` | `false` | Apply tab-local `:tcd` after a successful Vault switch |
| `checkbox_states` | `{ " ", "x" }` | Checkbox cycle and completion order |
| `note_id_func` | built-in CJK slug | Convert a title to a filename without `.md` |
| `on_vault_switch` | `nil` | `function(name, path)` called after a successful switch |
| `after_note_open` | `nil` | `function(path, opts)` called after direct plugin note opens |

`vault_path` is internal runtime state and must not be configured manually.

The default Note ID function keeps ASCII alphanumerics and CJK text, removes other
punctuation, replaces consecutive whitespace with `-`, and lowercases ASCII:

- `Hello World` → `hello-world`
- `我的笔记 2026` → `我的笔记-2026`
- `A & B!` → `a-b`

Custom behavior must be passed explicitly:

```lua
require("miniobsidian").setup({
  note_id_func = function(title)
    return os.date("%Y%m%d%H%M%S") .. "-" .. title:lower():gsub("%s+", "-")
  end,
  checkbox_states = { " ", "/", "x", "-" },
})
```

Directory options must be safe Vault-relative paths. Parent traversal, absolute
paths, hidden segments, NUL, Windows ADS and device names, and trailing dots/spaces
are rejected. `daily_template` receives the same Vault-boundary check when a Daily
Note is resolved.

### Obsidian configuration synchronization

With `sync_obsidian_config=true`, the plugin reads only:

- `.obsidian/app.json`
  - `newFileLocation="root"` → `notes_subdir=""`
  - `newFileLocation="folder"` + `newFileFolderPath` → `notes_subdir`
  - `attachmentFolderPath` (non-empty, not `.`) → `attachments_folder`

    > **Note:** If the active Vault has `attachmentFolderPath` configured in Obsidian,
    > synchronization will override the plugin default `attachments_folder = "Assets"`,
    > and `:ObsidianPasteFile` will write files to the Obsidian-configured directory.
    > To keep using the plugin default, set `attachments_folder` explicitly in
    > `setup()`, or leave the Obsidian attachment directory empty / set to `.`.

- `.obsidian/daily-notes.json`
  - `folder` → `dailies_folder`
  - supported Moment `format` → Lua `daily_date_format`
  - `template` → `daily_template`

Precedence is explicit user configuration, then the active Vault's Obsidian settings,
then plugin defaults. Synchronized fields are rebuilt on every switch, so values do
not leak between Vaults. Synchronized directory fields are validated before the
active Vault changes; an unsafe directory leaves the previous Vault active.
Unsupported Moment tokens are not synchronized. A missing, ambiguous, or unsafe
`daily_template` aborts Daily Note creation when that workflow runs.

`setup(opts)` returns `true` on success. Invalid configuration, no valid Vault, or a
synchronized directory that fails validation returns `false, errors` and does not
fire `MiniObsidianSetup`. Calling `setup()` again resets runtime configuration and
caches before discovery; unlike a runtime `ObsidianSwitchVault`, failure is not
guaranteed to preserve the old state.

## blink.cmp completion

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

Completion is enabled only in Markdown buffers inside the active Vault. `[[` lists
note targets; duplicate basenames insert qualified Vault-relative IDs, and previews
read the first ten lines. `- [`, `* [`, and `+ [` list `checkbox_states` in configured
order.

## Commands

| Command | Description |
|---|---|
| `:ObsidianNew[!] [title]` | Create or open a note in `notes_subdir`; `!` passes `switch_root=true` |
| `:ObsidianNewHere` | Create in the selected file-tree directory, falling back to `notes_subdir` when no explorer is detected |
| `:ObsidianSwitchVault` | Select the active Vault |
| `:ObsidianSwitch` | Fuzzy-find Markdown notes within `picker_scope` through snacks |
| `:ObsidianSearch [query]` | Search Markdown within `picker_scope` through snacks and ripgrep |
| `:ObsidianBacklinks` | List resolved Wikilinks to the current note and jump to the reference without LSP |
| `:ObsidianMove [target]` | Move the current Markdown note or file-tree selection and update resolved Wikilinks; `.md` is optional |
| `:ObsidianRename [new-name]` | Rename the current Markdown note or file-tree selection in place and update references; `.md` is optional |
| `:ObsidianTemplate` | Select, render, and insert a recursive template |
| `:ObsidianNewTemplate [name]` | Create or open a template without replacing it |
| `:ObsidianPasteFile [name]` | Paste macOS clipboard files or images into attachments_folder and insert a relative Markdown link; images use `![](path)`, other files use `[filename](path)` |
| `:ObsidianToday[!]` | Open or create today's note; `!` passes `switch_root=true` |
| `:ObsidianSetup` | Call `setup()` with defaults, mainly for tests or setups without a plugin manager |

`ObsidianNewHere` supports snacks explorer, neo-tree, nvim-tree, oil.nvim, and netrw.
If it detects a directory outside the active Vault, it stops instead of falling back.

`ObsidianMove` accepts a Vault-relative Note ID. For example,
`:ObsidianMove Archive/Project` moves the current note to `Archive/Project.md`.
A trailing `/`, or an existing directory, preserves the current filename. Backlinks are
updated from their pre-move resolution, so ambiguous links are not guessed. A short link
stays short when the new basename is unique across the Vault, becomes Vault-qualified
when it would be ambiguous, and an originally qualified link stays qualified. Aliases,
headings, block IDs, `.md` suffixes, and embeds are preserved. Text inside fenced code, inline code, and
Obsidian `%%` comments is not treated as a link. The operation stops when another Vault
Markdown buffer has unsaved edits, and attempts a full rollback on write failure.
After success, supported LSP clients receive rename and watched-file notifications so
definition/reference indexes can switch to the new path immediately.
Both commands work from a Markdown buffer or on the selected `.md` file in snacks
explorer, neo-tree, nvim-tree, oil.nvim, or netrw. A directory or non-Markdown
selection is rejected.

Move targets support Vault-directory completion. Use `:ObsidianMove <Tab>` to list
directories or type a prefix such as `:ObsidianMove Pro<Tab>`. The interactive input
opened by a keymap or argument-less command supports the same Tab completion.
In that completion menu, use Down/j for the next item and Up/h/k for the previous
item. Candidates end in `/`, so choosing one preserves the current filename.

`ObsidianRename` renames within the current directory, for example
`:ObsidianRename Project Plan`. It rejects directory separators; use `ObsidianMove`
when the directory must also change. When the filename changes, a frontmatter `title`
and the first level-one heading are synchronized if they still exactly match the old
filename. Custom titles are preserved. References follow the same shortest-unambiguous
link policy.

## Wikilinks

Navigation supports:

| Form | Behavior |
|---|---|
| `[[Note]]` | Resolve a unique basename |
| `[[Folder/Note]]` | Resolve an exact Vault-relative Note ID |
| `[[Note\|Alias]]` | Preserve the alias and navigate to `Note` |
| `[[Note#Heading]]` | Open the note and locate the heading |
| `[[Note#^block-id]]` | Open the note and locate an end-of-line block ID |

Duplicate basenames require explicit selection. After confirmation, a missing target
is created relative to the Vault: `[[Folder/Note]]` becomes `Folder/Note.md`, while a
bare `[[Note]]` is created at the Vault root rather than in `notes_subdir`.
Current-document links such as `[[#Heading]]` are not supported. Completion provides
note targets only; it does not complete aliases, headings, or block IDs.

Heading lookup matches visible heading text case-insensitively and supports `-1`,
`-2`, and later suffixes for duplicate headings; it is not a complete implementation
of Obsidian's anchor slug algorithm. Block IDs match only at the end of a line.

`:ObsidianBacklinks` scans the whole Vault with the same resolution rules used for link
navigation. Ambiguous short links are not guessed; qualified links, aliases, headings,
block IDs, and embeds are recognized. Fenced code, inline code, and `%%` comments are
ignored. Results open in a Snacks Picker and jump directly to the reference line without
using LSP.

```lua
vim.keymap.set("n", "<CR>", function()
  require("miniobsidian.link").follow_link_or_toggle()
end)
```

## Checkboxes

`checkbox.toggle()` cycles through `checkbox_states`. Plain `- item`, `* item`, and
`+ item` lines are upgraded to the first state. `checkbox.clear()` restores a checkbox
to a plain list item.

```lua
vim.keymap.set("n", "<leader>nt", function() require("miniobsidian.checkbox").toggle() end)
vim.keymap.set("n", "<leader>nc", function() require("miniobsidian.checkbox").clear() end)
```

## Templates and Daily Notes

Template variables are case-insensitive:

| Variable | Meaning |
|---|---|
| `{{date}}` | Date using `daily_date_format` |
| `{{time}}` | Current time as `HH:MM` |
| `{{title}}` / `{{filename}}` | Current filename without extension |
| `{{yesterday}}` / `{{tomorrow}}` | Previous/next local calendar day, including DST transitions |
| `{{date:FORMAT}}` | Custom date using the supported Moment-style subset |

`FORMAT` supports `YYYY`, `YY`, `MMMM`, `MMM`, `MM`, `DD`, `dddd`, `ddd`, `HH`,
`hh`, `mm`, `ss`, `A`, `a`, and `[literal]`. Unsupported tokens fail the render;
unknown ordinary variables remain unchanged and produce warnings.

An explicitly configured `daily_date_format` uses Lua `os.date` syntax. An Obsidian
Moment format is applied only when every token belongs to the supported subset above.

The Daily target is `dailies_folder/os.date(daily_date_format).md`. An existing file
opens without reading its former template. A new file renders `daily_template`, or
uses `daily_default_content` when no template is configured. Missing or ambiguous
templates abort creation.

## Clipboard file paste

macOS only. Finder-copied files of any type are copied into `attachments_folder`
preserving their original format; images (PNG, JPEG, GIF, WEBP, HEIC, HEIF, TIFF,
BMP, or SVG) are inserted as `![](path)`, while other files are inserted as
`[filename](path)`. Screenshots and browser images are converted to PNG/JPG/GIF.

If any supported extension already uses the requested name, the plugin selects
`name-1`, `name-2`, and so on. Files are written to a same-directory temporary file
and then published with exclusive no-replace semantics.

## Callbacks and events

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

- `after_note_open(path, opts)` runs for `new_note()` (including an existing Note ID),
  creation after a missing Wikilink, and Daily Note workflows. Existing-link
  navigation, templates, quick switch, and search do not call it. `opts.switch_root`
  comes from command `!`. The
  `MiniObsidianNoteOpened` event fires first.
- `on_vault_switch(name, path)` runs after configuration is committed, the note cache
  is invalidated, and `MiniObsidianVaultSwitch` fires. Initial `setup()` does not fire
  this event or callback; `change_cwd_on_switch` also applies only to runtime switches.

`quick_switch()` and `search()` let snacks open files and therefore do not invoke
`after_note_open`. Use `BufEnter` for picker-opened notes:

```lua
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*.md",
  callback = function(ev)
    local core = require("miniobsidian")
    local path = vim.api.nvim_buf_get_name(ev.buf)
    if core.in_vault(path) then
      -- Refresh a tree, statusline, or project root here.
    end
  end,
})
```

| Event | data | Timing |
|---|---|---|
| `User MiniObsidianSetup` | none | After successful `setup()` |
| `User MiniObsidianVaultSwitch` | `{ name, path }` | After a successful switch |
| `User MiniObsidianNoteOpened` | `{ path, opts }` | After a direct plugin note open |
| `User MiniObsidianNoteMoved` | `{ operation, old_path, new_path, updated_files, updated_links, updated_identity_fields }` | After the note and its references are updated |
| `User MiniObsidianNoteRenamed` | `{ operation, old_path, new_path, updated_files, updated_links, updated_identity_fields }` | After a rename and its references are updated |

## Lua API

Common public API:

```lua
local core = require("miniobsidian")
core.setup({})                   -- true, or false, errors
core.default_config()
core.validate_config(config)
core.get_all_notes(force)
core.invalidate_cache()
core.update_note_cache(path)     -- single-path update after a plugin write
core.get_cache_stamp()
core.note_stem(path)
core.in_vault(path)

local note = require("miniobsidian.note")
note.new_note()                  -- interactive title prompt
note.new_note("Title", { switch_root = true })
note.new_note_here()
note.new_note_in_dir(absolute_dir)
note.quick_switch()
note.search()
note.search("query")
note.backlinks()
note.follow_or_create(wikilink_or_parsed)
note.move("Archive/New Path")    -- move current note and update Wikilinks
note.rename("New Filename")     -- rename in place and update Wikilinks

require("miniobsidian.vault").pick_and_switch()
require("miniobsidian.vault").do_switch({ name = "Personal", path = "/abs/vault" })
require("miniobsidian.daily").open_today()
require("miniobsidian.daily").resolve_today()
require("miniobsidian.template").insert()
require("miniobsidian.template").new_template()
require("miniobsidian.link").link_at_cursor()
require("miniobsidian.link").follow_link_or_toggle()
require("miniobsidian.checkbox").toggle()
require("miniobsidian.checkbox").clear()
require("miniobsidian.image").paste_file()
```

The no-argument calls above use interactive input or defaults. `resolve_today()` is a
read-only planning API returning `plan, nil` or `nil, error`; it does not create or
open a file.

Lower-level integration helpers may change more readily: `wikilink.*`,
`config_sync.*`, `path.*`, `fs.*`, `image.resolve_for_snacks`, and `completion.new`.

User callback failures are isolated and reported at WARN level; they do not interrupt
note-open or Vault-switch workflows.

## Suggested keymaps

```lua
vim.keymap.set("n", "<leader>nn", function() require("miniobsidian.note").new_note() end)
vim.keymap.set("n", "<leader>no", function() require("miniobsidian.note").quick_switch() end)
vim.keymap.set("n", "<leader>ns", function() require("miniobsidian.note").search() end)
vim.keymap.set("n", "<leader>nd", function() require("miniobsidian.daily").open_today() end)
vim.keymap.set("n", "<leader>np", function() require("miniobsidian.image").paste_file() end)
```

The plugin defines no keymaps.

## Health and tests

```vim
:checkhealth miniobsidian
:help miniobsidian
:help miniobsidian-zh
```

```sh
make ci
```

Health checks cover the Neovim version, optional dependencies, configuration validity,
Vault discovery source, and the active Vault.

Full development verification also requires `stylua`, `selene`, and `plenary.nvim`;
override the Makefile defaults with `NVIM` and `PLENARY_DIR` when needed.

## Acknowledgements

- [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim) by [@epwalsh](https://github.com/epwalsh) — the original inspiration for this plugin. If you need a full-featured, battle-tested Obsidian client for Neovim, use that instead.
- [snacks.nvim](https://github.com/folke/snacks.nvim) by [@folke](https://github.com/folke) — powers the picker UI.
- [blink.cmp](https://github.com/Saghen/blink.cmp) by [@Saghen](https://github.com/Saghen) — powers the autocomplete integration.

## License

MIT
