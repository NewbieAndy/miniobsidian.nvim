local M = {}

local function fail(code, message)
  return nil, code .. ": " .. message
end

local TOKENS = {
  { "YYYY", "%Y" },
  { "MMMM", "%B" },
  { "dddd", "%A" },
  { "MMM", "%b" },
  { "ddd", "%a" },
  { "YY", "%y" },
  { "MM", "%m" },
  { "DD", "%d" },
  { "HH", "%H" },
  { "hh", "%I" },
  { "mm", "%M" },
  { "ss", "%S" },
  { "A", "%p" },
  { "a", "%p" },
}

---Convert the supported Obsidian/Moment date format subset to os.date.
---@param format string
---@return string|nil
---@return string|nil
function M.moment_to_lua(format)
  if type(format) ~= "string" or format == "" then
    return fail("EMPTY_DATE_FORMAT", "Failed to parse date format: input is empty")
  end

  local output = {}
  local index = 1
  while index <= #format do
    local char = format:sub(index, index)
    if char == "[" then
      local closing = format:find("]", index + 1, true)
      if not closing then
        return fail("UNCLOSED_LITERAL", "Failed to parse date format: contains an unclosed literal")
      end
      output[#output + 1] = format:sub(index + 1, closing - 1):gsub("%%", "%%%%")
      index = closing + 1
    elseif char:match("%a") then
      local matched = false
      for _, token in ipairs(TOKENS) do
        if format:sub(index, index + #token[1] - 1) == token[1] then
          output[#output + 1] = token[2]
          index = index + #token[1]
          matched = true
          break
        end
      end
      if not matched then
        local unsupported = format:sub(index):match("^%a+") or char
        return fail(
          "UNSUPPORTED_MOMENT_TOKEN",
          "Failed to parse date format: unsupported Moment token: " .. unsupported
        )
      end
    else
      output[#output + 1] = char == "%" and "%%" or char
      index = index + 1
    end
  end
  return table.concat(output)
end

---Shift by a local calendar day, avoiding fixed-second DST arithmetic.
---@param timestamp number
---@param days integer
---@return number
function M.shift_calendar_day(timestamp, days)
  local value = os.date("*t", timestamp)
  value.day = value.day + days
  value.hour = 12
  value.min = 0
  value.sec = 0
  value.isdst = nil
  return os.time(value)
end

---@param content string
---@param context {timestamp?: number, title?: string, date_format?: string}
---@return string|nil
---@return string[]
---@return string|nil
function M.render(content, context)
  context = context or {}
  local timestamp = context.timestamp or os.time()
  local date_format = context.date_format or "%Y-%m-%d"
  local title = context.title or ""
  local warnings = {}
  local warned = {}

  local values = {
    date = os.date(date_format, timestamp),
    time = os.date("%H:%M", timestamp),
    title = title,
    filename = title,
    yesterday = os.date(date_format, M.shift_calendar_day(timestamp, -1)),
    tomorrow = os.date(date_format, M.shift_calendar_day(timestamp, 1)),
  }

  local render_error
  local rendered = content:gsub("{{([^{}]+)}}", function(expression)
    local key = expression:lower()
    if values[key] ~= nil then
      return values[key]
    end

    local custom_format = expression:match("^[Dd][Aa][Tt][Ee]:(.+)$")
    if custom_format then
      local lua_format, err = M.moment_to_lua(custom_format)
      if not lua_format then
        render_error = err
        return "{{" .. expression .. "}}"
      end
      return os.date(lua_format, timestamp)
    end

    local original = "{{" .. expression .. "}}"
    if not warned[original] then
      warned[original] = true
      warnings[#warnings + 1] = "Preserved unknown template variable " .. original
    end
    return original
  end)

  if render_error then
    return nil, warnings, render_error
  end
  return rendered, warnings
end

return M
