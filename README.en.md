# miniobsidian.nvim

A lightweight, standalone Obsidian workflow plugin for Neovim.

The plugin focuses on the editor experience: Vault discovery, note creation and search,
Wikilinks, templates, Daily Notes, checkboxes, and image paste. It does not integrate
with external CLIs or Agent frameworks and does not coordinate writes across clients.

## Features

- Automatic Vault discovery from Obsidian configuration or a configured parent directory
- Note creation in the default folder or the current file-tree directory
- Fast note switching and full-text search through `snacks.nvim`
- Wikilink navigation and completion with aliases, fragments, and ambiguity handling
- Checkbox state cycling and blink.cmp completion
- Recursive templates and Obsidian-style date variables
- Daily Notes configuration synchronization
- macOS clipboard image paste
- Vault path, symlink escape, and cross-platform filename checks
- No-replace file creation: existing notes are never truncated by create commands

## Scope

Obsidian, Neovim, sync software, and other tools may all modify the same Markdown Vault.
miniobsidian.nvim deliberately does not implement revisions, optimistic locking, external
change watchers, three-way merge UI, or cross-client transactions. File changes and write
conflicts use Neovim's native behavior; recovery belongs to Git, sync history, or the user's
workflow.

The plugin still enforces its own local correctness: targets must remain inside the active
Vault; note, template, and Daily Note creation never replace an existing path; and I/O
failures are reported.

## Requirements

- Neovim >= 0.10.4
- `snacks.nvim` for switching/search, optional
- `blink.cmp` for completion, optional
- `ripgrep` for full-text search, optional
- `osascript` for image paste on macOS

## Installation

```lua
{
  "andy-neoaira/miniobsidian.nvim",
  ft = "markdown",
  cmd = {
    "ObsidianNew", "ObsidianNewHere", "ObsidianSwitchVault", "ObsidianSwitch",
    "ObsidianSearch", "ObsidianTemplate", "ObsidianNewTemplate",
    "ObsidianPasteImg", "ObsidianToday", "ObsidianSetup",
  },
  config = function()
    require("miniobsidian").setup()
  end,
}
```

Manual Vault configuration:

```lua
require("miniobsidian").setup({
  vaults_parent = "~/Documents/Obsidian",
  default_vault = "Personal",
  auto_discover = false,
  notes_subdir = "Notes",
  templates_folder = "Templates",
  attachments_folder = "Assets",
  dailies_folder = "Dailies",
  checkbox_states = { " ", "/", "x", "-" },
})
```

See `:help miniobsidian` for the full configuration, command, API, and event reference.

## Commands

| Command | Description |
|---|---|
| `:ObsidianNew[!] [title]` | Create or open a note in the default note directory |
| `:ObsidianNewHere` | Create a note in the current file-tree directory |
| `:ObsidianSwitchVault` | Switch the active Vault |
| `:ObsidianSwitch` | Quickly switch notes |
| `:ObsidianSearch [query]` | Full-text search |
| `:ObsidianTemplate` | Insert a template |
| `:ObsidianNewTemplate [name]` | Create or open a template |
| `:ObsidianPasteImg [name]` | Paste a clipboard image on macOS |
| `:ObsidianToday[!]` | Open or create today's note |
| `:ObsidianSetup` | Initialize with defaults |

Template variables include `{{date}}`, `{{time}}`, `{{title}}`, `{{filename}}`,
`{{yesterday}}`, `{{tomorrow}}`, and `{{date:YYYY/MM/DD}}`.

## Health and tests

```vim
:checkhealth miniobsidian
```

```sh
make ci
```

## License

MIT
