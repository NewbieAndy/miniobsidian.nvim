describe("checkbox", function()
  before_each(function()
    vim.cmd("enew!")
    require("miniobsidian").config.checkbox_states = { " ", "/", "x" }
  end)

  local function set_line(line)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  end

  local function line()
    return vim.api.nvim_get_current_line()
  end

  it("cycles configured states and wraps around", function()
    set_line("- [ ] task")
    require("miniobsidian.checkbox").toggle()
    assert.equals("- [/] task", line())
    require("miniobsidian.checkbox").toggle()
    assert.equals("- [x] task", line())
    require("miniobsidian.checkbox").toggle()
    assert.equals("- [ ] task", line())
  end)

  it("upgrades a plain list and clears it again", function()
    set_line("  * task")
    require("miniobsidian.checkbox").toggle()
    assert.equals("  * [ ] task", line())
    require("miniobsidian.checkbox").clear()
    assert.equals("  * task", line())
  end)

  it("resets unknown checkbox states to the first configured state", function()
    set_line("+ [?] question")
    require("miniobsidian.checkbox").toggle()
    assert.equals("+ [ ] question", line())
  end)

  it("does not modify ordinary text or Wikilink list items", function()
    set_line("plain text")
    require("miniobsidian.checkbox").toggle()
    assert.equals("plain text", line())
    set_line("- [[Note]]")
    require("miniobsidian.checkbox").toggle()
    assert.equals("- [[Note]]", line())
  end)
end)
