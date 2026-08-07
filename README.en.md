# miniobsidian.nvim

A lightweight, standalone Obsidian workflow plugin for Neovim. English · [中文](README.md)

`miniobsidian.nvim` focuses on the editor experience: Vault discovery and switching,
note creation and search, Wikilinks, templates, Daily Notes, checkboxes, and image
paste. It has no external CLI or Agent integration and does not coordinate writes
across clients.

## Features

- Discover Vaults from Obsidian configuration or a configured parent directory
- Create notes in the default folder or the current file-tree directory
- Switch and search Markdown notes through `snacks.nvim`
- Navigate and create Wikilinks with aliases, headings, block IDs, qualified paths,
  and duplicate-name disambiguation
- Complete note targets and checkbox states through `blink.cmp`, with note previews
- Cycle and clear checkboxes, including upgrading plain list items
- Select recursive templates and render Obsidian-style date variables
- Synchronize Obsidian's new-note and Daily Notes settings
- Paste macOS clipboard images with collision-safe incrementing names
- Enforce Vault boundaries, symlink containment, hidden-directory policy, and
  cross-platform filename rules
- Use no-replace publication for notes, templates, Daily Notes, and images

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
- `snacks.nvim` for switching and search, optional
- `blink.cmp` for Wikilink and checkbox completion, optional
- `ripgrep` for full-text search, optional
- `osascript` for image paste, macOS only

Core Vault, note, template, Daily Note, link navigation, and checkbox workflows remain
available without the optional dependencies.

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

Zero-config setup discovers Vaults from Obsidian's official `obsidian.json`. Manual
discovery example:

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
| `default_vault` | `""` | Initial Vault name; falls back to the first discovered entry |
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

Path options must be safe Vault-relative paths. Parent traversal, absolute paths,
hidden segments, NUL, Windows ADS and device names, and trailing dots/spaces are
rejected.

### Obsidian configuration synchronization

With `sync_obsidian_config=true`, the plugin reads only:

- `.obsidian/app.json`
  - `newFileLocation` / `newFileFolderPath` → `notes_subdir`
- `.obsidian/daily-notes.json`
  - `folder` → `dailies_folder`
  - `format` → `daily_date_format`
  - `template` → `daily_template`

Precedence is explicit user configuration, then the active Vault's Obsidian settings,
then plugin defaults. Synchronized fields are rebuilt on every switch, so values do
not leak between Vaults. The candidate configuration is fully validated before the
active Vault changes; unsafe settings leave the previous Vault active.

`setup(opts)` returns `true` on success. Invalid configuration, no valid Vault, or
unsafe synchronized settings return `false, errors` and do not fire
`MiniObsidianSetup`.

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
| `:ObsidianSwitch` | Fuzzy-find Markdown notes through snacks |
| `:ObsidianSearch [query]` | Search Markdown through snacks and ripgrep |
| `:ObsidianTemplate` | Select, render, and insert a recursive template |
| `:ObsidianNewTemplate [name]` | Create or open a template without replacing it |
| `:ObsidianPasteImg [name]` | Paste an image on macOS and insert a relative Markdown link |
| `:ObsidianToday[!]` | Open or create today's note; `!` passes `switch_root=true` |
| `:ObsidianSetup` | Call `setup()` with defaults, mainly for tests or setups without a plugin manager |

`ObsidianNewHere` supports snacks explorer, neo-tree, nvim-tree, oil.nvim, and netrw.
If it detects a directory outside the active Vault, it stops instead of falling back.

## Wikilinks

Navigation supports:

| Form | Behavior |
|---|---|
| `[[Note]]` | Resolve a unique basename |
| `[[Folder/Note]]` | Resolve an exact Vault-relative Note ID |
| `[[Note\|Alias]]` | Preserve the alias and navigate to `Note` |
| `[[Note#Heading]]` | Open the note and locate the heading |
| `[[Note#^block-id]]` | Open the note and locate an end-of-line block ID |

Duplicate basenames require explicit selection. A missing qualified target can be
created with the requested directory and filename after confirmation. Current-document
links such as `[[#Heading]]` are not supported. Completion provides note targets only;
it does not complete aliases, headings, or block IDs.

```lua
vim.keymap.set("n", "<CR>", function()
  require("miniobsidian.link").follow_link_or_toggle()
end)
```

## Checkboxes

`checkbox.toggle()` cycles through `checkbox_states`. Plain `- item`, `* item`, and
`+ item` lines are upgraded to the first state. `checkbox.clear()` restores a checkbox
to a plain list item.

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

The Daily target is `dailies_folder/os.date(daily_date_format).md`. An existing file
opens without reading its former template. A new file renders `daily_template`, or
uses `daily_default_content` when no template is configured. Missing or ambiguous
templates abort creation.

## Image paste

Image paste is macOS-only. Finder images preserve PNG, JPEG, GIF, WEBP, HEIC, HEIF,
TIFF, BMP, or SVG. Screenshots and browser images become PNG/JPG/GIF. Images are
stored under `attachments_folder`, and the inserted link is relative to the note.

If any supported image extension already uses the requested name, the plugin selects
`name-1`, `name-2`, and so on. It writes to a same-directory temporary file and then
publishes with exclusive no-replace semantics.

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
  is invalidated, and `MiniObsidianVaultSwitch` fires.

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

## Lua API

Common public API:

```lua
local core = require("miniobsidian")
core.setup(opts)                 -- true, or false, errors
core.default_config()
core.validate_config(config)
core.get_all_notes(force)
core.invalidate_cache()
core.update_note_cache(path)     -- single-path update after a plugin write
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

Lower-level integration helpers may change more readily: `wikilink.*`,
`config_sync.*`, `path.*`, `fs.*`, `image.resolve_for_snacks`, and `completion.new`.

User callback failures are isolated and reported at WARN level; they do not interrupt
note-open or Vault-switch workflows.

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

## License

MIT
