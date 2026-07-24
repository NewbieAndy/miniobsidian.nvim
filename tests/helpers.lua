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
  core.config.templates_folder = "Templates"
  core.config.daily_date_format = "%Y-%m-%d"
  core.invalidate_cache()
  return core
end

function M.cleanup(path)
  vim.cmd("silent! %bwipeout!")
  vim.fn.delete(path, "rf")
end

return M
