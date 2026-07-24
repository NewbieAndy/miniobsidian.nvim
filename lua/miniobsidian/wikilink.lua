local M = {}

local path_policy = require("miniobsidian.path")

local function trim(value)
  return value and value:match("^%s*(.-)%s*$") or nil
end

local function strip_md(value)
  return value:gsub("%.md$", "")
end

function M.parse(value)
  if type(value) ~= "string" then
    return nil, "INVALID_WIKILINK"
  end
  local inner = value:match("^%[%[(.*)%]%]$") or value
  local target_part, alias = inner:match("^(.-)|(.*)$")
  target_part = target_part or inner

  local target, fragment = target_part:match("^(.-)#(.*)$")
  target = trim(target or target_part)
  if not target or target == "" then
    return nil, "INVALID_WIKILINK"
  end

  local result = {
    target = path_policy.normalize(strip_md(target)),
    alias = alias and trim(alias) or nil,
    heading = nil,
    block = nil,
  }
  fragment = trim(fragment)
  if fragment and fragment ~= "" then
    if fragment:sub(1, 1) == "^" then
      result.block = fragment:sub(2)
    else
      result.heading = fragment
    end
  end
  return result
end

local function note_id(vault, absolute)
  local resolved = path_policy.resolve(vault, absolute, { allow_absolute = true })
  return resolved and strip_md(resolved.logical) or nil
end

function M.resolve(link, notes, vault)
  local target = path_policy.normalize(strip_md(link.target))
  local candidates = {}
  for _, absolute in ipairs(notes) do
    local id = note_id(vault, absolute)
    if id then
      candidates[#candidates + 1] = { id = id, path = absolute }
    end
  end
  table.sort(candidates, function(a, b)
    return a.id < b.id
  end)

  local matches = {}
  local exact = {}
  local has_directory = target:find("/", 1, true) ~= nil
  for _, candidate in ipairs(candidates) do
    local comparable = has_directory and candidate.id or (candidate.id:match("([^/]+)$") or candidate.id)
    if comparable == target then
      exact[#exact + 1] = candidate
    elseif comparable:lower() == target:lower() then
      matches[#matches + 1] = candidate
    end
  end

  local selected = #exact > 0 and exact or matches
  if #selected == 1 then
    return selected[1]
  end
  if #selected > 1 then
    local ids = {}
    for _, item in ipairs(selected) do
      ids[#ids + 1] = item.id
    end
    return nil, { code = "AMBIGUOUS_NOTE", candidates = ids }
  end
  return nil, { code = "NOTE_NOT_FOUND", candidates = {} }
end

local function visible_heading(line)
  local text = line:match("^%s*#+%s+(.+)$")
  if not text then
    return nil
  end
  return trim(text:gsub("%s+#+%s*$", ""):gsub("[`*_]", ""))
end

function M.locate_fragment(absolute, link)
  if not link.heading and not link.block then
    return nil
  end
  local lines = vim.fn.readfile(absolute)
  if link.block then
    local escaped = vim.pesc(link.block)
    for index, line in ipairs(lines) do
      if line:match("%^" .. escaped .. "%s*$") then
        return index
      end
    end
    return nil, "FRAGMENT_NOT_FOUND"
  end

  local wanted = link.heading:lower()
  local counts = {}
  for index, line in ipairs(lines) do
    local heading = visible_heading(line)
    if heading then
      local base = heading:lower()
      local occurrence = counts[base] or 0
      counts[base] = occurrence + 1
      local anchor = occurrence == 0 and base or (base .. "-" .. occurrence)
      if wanted == base or wanted == anchor then
        return index
      end
    end
  end
  return nil, "FRAGMENT_NOT_FOUND"
end

return M
