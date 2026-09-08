-- Shared byte-preserving Markdown scanning for backlinks and note rewrites.
local M = {}

local function fence(line)
  local indent, marker, rest = line:match("^( *)([`~]+)(.*)$")
  if not marker or #indent > 3 or #marker < 3 then
    return nil
  end
  if not (marker:match("^`+$") or marker:match("^~+$")) then
    return nil
  end
  return marker, rest
end

local function code_end(content, start, length)
  local position = start
  local continuation = false
  while position <= #content do
    local newline = content:find("\n", position, true)
    local last_byte = newline and newline - 1 or #content
    local line = content:sub(position, last_byte)
    -- Code spans may cross soft line breaks, but cannot cross a paragraph or fence.
    if continuation and (line:match("^%s*$") or fence(line)) then
      return nil
    end
    local search = 1
    while search <= #line do
      local first, last = line:find("`+", search)
      if not first then
        break
      end
      if last - first + 1 == length then
        return position + last - 1
      end
      search = last + 1
    end
    position = newline and newline + 1 or #content + 1
    continuation = true
  end
end

-- Track common list/blockquote containers before interpreting block indentation.
local function block_content(line, state)
  local text = line
  while true do
    local rest = text:match("^ ? ? ?> ?(.*)$")
    if not rest then
      break
    end
    text = rest
  end
  if state.fence then
    local spaces = #(text:match("^ *") or "")
    return state.list_indent and spaces >= state.list_indent and text:sub(state.list_indent + 1) or text
  end
  local indent, marker = text:match("^( *)([-*+]%s+)")
  if not marker then
    indent, marker = text:match("^( *)(%d+[.)]%s+)")
  end
  if marker then
    state.list_indent = #indent + #marker
    return text:sub(state.list_indent + 1)
  end
  local spaces = #(text:match("^ *") or "")
  if state.list_indent and spaces >= state.list_indent then
    return text:sub(state.list_indent + 1)
  end
  if text:match("%S") then
    state.list_indent = nil
  end
  return text
end

---Visit lines with a same-length mask hiding code, comments and escaped punctuation.
---The callback can replace a line and return a change count. Original newlines survive.
---@param content string
---@param callback fun(line: string, visible: string, number: integer): string?, integer?
---@return string, integer
function M.transform(content, callback)
  local output, count = {}, 0
  local position, number = 1, 0
  local state = {}
  while position <= #content do
    local newline = content:find("\n", position, true)
    local last = newline and newline - 1 or #content
    local ending = newline and "\n" or ""
    local line = content:sub(position, last)
    if line:sub(-1) == "\r" then
      line = line:sub(1, -2)
      ending = "\r" .. ending
    end
    number = number + 1
    local block = block_content(line, state)
    local marker, rest = fence(block)
    local visible
    if state.fence then
      if marker and marker:sub(1, 1) == state.fence:sub(1, 1) and #marker >= #state.fence and rest:match("^%s*$") then
        state.fence = nil
      end
      visible = string.rep(" ", #line)
    elseif
      not state.comment
      and not state.code_end
      and marker
      and not (marker:sub(1, 1) == "`" and rest:find("`", 1, true))
    then
      state.fence = marker
      visible = string.rep(" ", #line)
    elseif not state.comment and not state.code_end and (block:match("^    ") or block:match("^\t")) then
      visible = string.rep(" ", #line)
    else
      local pieces, index = {}, 1
      local function hide(last_index)
        pieces[#pieces + 1] = string.rep(" ", last_index - index + 1)
        index = last_index + 1
      end
      while index <= #line do
        if state.comment then
          local close = line:find(state.comment, index, true)
          local stop = close and close + #state.comment - 1 or #line
          hide(stop)
          if close then
            state.comment = nil
          end
        elseif state.code_end then
          local stop = math.min(#line, state.code_end - position + 1)
          hide(stop)
          if position + stop - 1 == state.code_end then
            state.code_end = nil
          end
        elseif line:sub(index, index) == "\\" and line:sub(index + 1, index + 1):match("%p") then
          hide(index + 1)
        elseif line:sub(index, index + 1) == "%%" then
          state.comment = "%%"
          hide(index + 1)
        elseif line:sub(index, index + 3) == "<!--" then
          state.comment = "-->"
          hide(index + 3)
        elseif line:sub(index, index) == "`" then
          local run = line:sub(index):match("^`+")
          state.code_end = code_end(content, position + index + #run - 1, #run)
          if state.code_end then
            hide(index + #run - 1)
          else
            pieces[#pieces + 1] = run
            index = index + #run
          end
        else
          pieces[#pieces + 1] = line:sub(index, index)
          index = index + 1
        end
      end
      visible = table.concat(pieces)
    end
    local rewritten, changes = callback(line, visible, number)
    output[#output + 1] = (rewritten or line) .. ending
    count = count + (changes or 0)
    position = newline and newline + 1 or #content + 1
  end
  return table.concat(output), count
end

---Visit/replace only Wikilinks exposed by the shared scanner.
function M.wikilinks(line, visible, callback)
  local output, position, count = {}, 1, 0
  while true do
    local first, last = visible:find("%[%[.-%]%]", position)
    if not first then
      break
    end
    output[#output + 1] = line:sub(position, first - 1)
    local replacement = callback(line:sub(first + 2, last - 2), first - 1)
    local original = line:sub(first, last)
    output[#output + 1] = replacement or original
    if replacement and replacement ~= original then
      count = count + 1
    end
    position = last + 1
  end
  output[#output + 1] = line:sub(position)
  return table.concat(output), count
end

return M
