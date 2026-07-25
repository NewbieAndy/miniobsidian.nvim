local M = {}

function M.temp_vault()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/.obsidian", "p")
  vim.fn.mkdir(root .. "/Notes", "p")
  return root
end

function M.configure(vault)
  local core = require("miniobsidian")
  core.config.vault_path = vault
  core.config.notes_subdir = "Notes"
  core.config.dailies_folder = "Dailies"
  core.config.daily_template = ""
  core.config.daily_default_content = ""
  core.config.templates_folder = "Templates"
  core.config.daily_date_format = "%Y-%m-%d"
  core.config.external_change_mode = "prompt"
  core.config.external_check_interval_ms = 1000
  core.config.external_watch_debounce_ms = 100
  core.config.watch_external_changes = true
  core.config.change_cwd_on_switch = false
  core.config.picker_scope = "notes"
  core.config.cli = {
    enabled = false,
    command = "obs-cli",
    timeout_ms = 3000,
  }
  core.invalidate_cache()
  return core
end

function M.cleanup(path)
  vim.cmd("silent! %bwipeout!")
  vim.fn.delete(path, "rf")
end

return M
