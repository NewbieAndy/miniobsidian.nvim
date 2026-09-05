local M = {}

local datetime = require("miniobsidian.datetime")
local path_policy = require("miniobsidian.path")
local wikilink = require("miniobsidian.wikilink")

local function resolve_template(core, template_id)
  local logical = template_id:gsub("%.md$", "") .. ".md"
  local safe, safe_err = path_policy.validate_logical(logical)
  if not safe then
    return nil, safe_err
  end

  local link = assert(wikilink.parse(template_id))
  local resolved, resolve_err = wikilink.resolve(link, core.get_all_notes(true), core.config.vault_path)
  if not resolved then
    local detail = resolve_err.code
    if resolve_err.candidates and #resolve_err.candidates > 0 then
      detail = detail .. ": " .. table.concat(resolve_err.candidates, ", ")
    end
    return nil, detail
  end
  return resolved.path
end

---Resolve today's target and initial bytes without modifying the Vault.
---@param opts? {timestamp?: number}
---@return {path: string, logical: string, date: string, content: string, warnings: string[]}|nil
---@return string|nil
function M.resolve_today(opts)
  opts = opts or {}
  local core = require("miniobsidian")
  local cfg = core.config
  local timestamp = opts.timestamp or os.time()
  local date_str = os.date(cfg.daily_date_format, timestamp)
  local logical = cfg.dailies_folder == "" and (date_str .. ".md") or (cfg.dailies_folder .. "/" .. date_str .. ".md")
  local resolved, resolve_err = path_policy.resolve(cfg.vault_path, logical)
  if not resolved then
    return nil, "Daily note path is unsafe: " .. tostring(resolve_err)
  end
  if vim.fn.filereadable(resolved.path) == 1 then
    return {
      path = resolved.path,
      logical = resolved.logical,
      date = date_str,
      content = "",
      warnings = {},
      exists = true,
    }
  end

  local source = cfg.daily_default_content or ""
  if cfg.daily_template and cfg.daily_template ~= "" then
    local template_path, template_err = resolve_template(core, cfg.daily_template)
    if not template_path then
      return nil, "Daily note template cannot be resolved: " .. tostring(template_err)
    end
    source, template_err = require("miniobsidian.fs").read(template_path)
    if not source then
      return nil, "Daily note template cannot be read: " .. tostring(template_err)
    end
  end

  local content, warnings, render_err = datetime.render(source, {
    timestamp = timestamp,
    title = date_str,
    date_format = cfg.daily_date_format,
  })
  if not content then
    return nil, "Daily note template render failed: " .. tostring(render_err)
  end
  return {
    path = resolved.path,
    logical = resolved.logical,
    date = date_str,
    content = content,
    warnings = warnings,
    exists = false,
  }
end

---Open today's Daily Note, creating it only when absent.
---@param opts? {switch_root?: boolean, timestamp?: number}
function M.open_today(opts)
  opts = opts or {}
  local core = require("miniobsidian")
  local plan, plan_err = M.resolve_today(opts)
  if not plan then
    core.notify(plan_err, vim.log.levels.ERROR)
    return
  end

  vim.fn.mkdir(vim.fn.fnamemodify(plan.path, ":h"), "p")
  local is_new, create_err = require("miniobsidian.fs").create_exclusive(plan.path, plan.content)
  if is_new == nil then
    core.notify("Failed to create daily note: " .. tostring(create_err), vim.log.levels.ERROR)
    return
  end
  if is_new then
    core.update_note_cache(plan.path)
    for _, warning in ipairs(plan.warnings) do
      core.notify(warning, vim.log.levels.WARN)
    end
  end

  vim.schedule(function()
    vim.cmd("edit " .. vim.fn.fnameescape(plan.path))
    core.after_note_open(plan.path, opts)
  end)
end

return M
