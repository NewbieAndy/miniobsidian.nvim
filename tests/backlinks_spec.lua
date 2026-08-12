local helpers = require("tests.helpers")

describe("backlinks", function()
  local vault
  local target
  local previous_snacks

  before_each(function()
    vault = helpers.temp_vault()
    helpers.configure(vault)
    target = vault .. "/Notes/Target.md"
    vim.fn.writefile({ "# Target" }, target)
    previous_snacks = package.loaded.snacks
  end)

  after_each(function()
    package.loaded.snacks = previous_snacks
    package.loaded["miniobsidian.backlinks"] = nil
    helpers.cleanup(vault)
  end)

  it("collects resolved references with exact locations and ignores code and comments", function()
    local reference = vault .. "/Notes/Reference.md"
    vim.fn.writefile({
      "[[Target]]",
      "prefix [[Notes/Target|Alias]] suffix",
      "![[Target#Heading]]",
      "`[[Target]]`",
      "%% [[Target]] %%",
      "```lua",
      "[[Target]]",
      "```",
      "[[Other]]",
      "[[Target#^block-id]]",
    }, reference)
    require("miniobsidian").invalidate_cache()

    local items = assert(require("miniobsidian.backlinks").collect(target))
    assert.equals(4, #items)
    assert.same({ 1, 0 }, items[1].pos)
    assert.same({ 2, 7 }, items[2].pos)
    assert.same({ 3, 1 }, items[3].pos)
    assert.same({ 10, 0 }, items[4].pos)
    assert.equals(reference, items[1].file)
  end)

  it("does not guess ambiguous short links", function()
    vim.fn.mkdir(vault .. "/Areas", "p")
    vim.fn.writefile({ "# Other Target" }, vault .. "/Areas/Target.md")
    local reference = vault .. "/Notes/Reference.md"
    vim.fn.writefile({
      "[[Target]]",
      "[[Notes/Target]]",
      "[[Areas/Target]]",
    }, reference)
    require("miniobsidian").invalidate_cache()

    local items = assert(require("miniobsidian.backlinks").collect(target))
    assert.equals(1, #items)
    assert.same({ 2, 0 }, items[1].pos)
  end)

  it("uses loaded buffer text and opens a jumpable Snacks picker", function()
    local reference = vault .. "/Notes/Reference.md"
    vim.fn.writefile({ "no reference on disk" }, reference)
    vim.cmd("edit " .. vim.fn.fnameescape(reference))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved [[Target]]" })
    require("miniobsidian").invalidate_cache()

    local captured
    package.loaded.snacks = {
      picker = {
        pick = function(opts)
          captured = opts
        end,
      },
    }
    require("miniobsidian.backlinks").open(target)

    assert.equals(" Backlinks: Notes/Target", captured.title)
    assert.equals(vault, captured.cwd)
    assert.equals("file", captured.format)
    assert.equals("file", captured.preview)
    assert.equals("jump", captured.confirm)
    assert.equals(1, #captured.items)
    assert.same({ 1, 8 }, captured.items[1].pos)
  end)
end)
