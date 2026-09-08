local helpers = require("tests.helpers")
local wikilink = require("miniobsidian.wikilink")

describe("wikilink", function()
  local vault

  before_each(function()
    vault = helpers.temp_vault()
    helpers.configure(vault)
  end)

  after_each(function()
    helpers.cleanup(vault)
  end)

  it("parses target, alias, heading, and block independently", function()
    local heading = assert(wikilink.parse("[[Folder/Note#Heading|Alias]]"))
    assert.same({ target = "Folder/Note", alias = "Alias", heading = "Heading", block = nil }, heading)
    local block = assert(wikilink.parse("[[Note#^block-id|Shown]]"))
    assert.same({ target = "Note", alias = "Shown", heading = nil, block = "block-id" }, block)
  end)

  it("returns ambiguity for a duplicate basename and exact path for a qualified target", function()
    vim.fn.mkdir(vault .. "/Areas", "p")
    vim.fn.mkdir(vault .. "/Projects/Alpha", "p")
    vim.fn.writefile({ "# Areas" }, vault .. "/Areas/Index.md")
    vim.fn.writefile({ "# Project" }, vault .. "/Projects/Alpha/Index.md")
    local notes = { vault .. "/Areas/Index.md", vault .. "/Projects/Alpha/Index.md" }

    local result, err = wikilink.resolve(assert(wikilink.parse("[[Index]]")), notes, vault)
    assert.is_nil(result)
    assert.equals("AMBIGUOUS_NOTE", err.code)
    assert.same({ "Areas/Index", "Projects/Alpha/Index" }, err.candidates)

    local exact = assert(wikilink.resolve(assert(wikilink.parse("[[Projects/Alpha/Index]]")), notes, vault))
    assert.equals("Projects/Alpha/Index", exact.id)
  end)

  it("matches the pinned duplicate-note fixture", function()
    local root = vim.env.MINIOBSIDIAN_ROOT .. "/tests/fixtures/duplicate-note-names"
    local notes = vim.fn.globpath(root, "**/*.md", false, true)
    local _, err = wikilink.resolve(assert(wikilink.parse("[[Index]]")), notes, root)
    assert.equals("AMBIGUOUS_NOTE", err.code)
    assert.same({ "Areas/Index", "Projects/Alpha/Index" }, err.candidates)
    local exact = assert(wikilink.resolve(assert(wikilink.parse("[[Projects/Alpha/Index]]")), notes, root))
    assert.equals("Projects/Alpha/Index", exact.id)
  end)

  it("locates headings, duplicate anchors, and exact block ids", function()
    local note = vault .. "/Notes/Fragments.md"
    vim.fn.writefile({ "# Intro", "text", "# Intro", "block ^block-id" }, note)
    assert.equals(1, wikilink.locate_fragment(note, assert(wikilink.parse("[[Fragments#Intro]]"))))
    assert.equals(3, wikilink.locate_fragment(note, assert(wikilink.parse("[[Fragments#Intro-1]]"))))
    assert.equals(4, wikilink.locate_fragment(note, assert(wikilink.parse("[[Fragments#^block-id]]"))))
  end)

  it("prompts for disambiguation instead of opening the first duplicate", function()
    vim.fn.mkdir(vault .. "/Areas", "p")
    vim.fn.mkdir(vault .. "/Projects", "p")
    vim.fn.writefile({ "# A" }, vault .. "/Areas/Index.md")
    vim.fn.writefile({ "# B" }, vault .. "/Projects/Index.md")
    require("miniobsidian").invalidate_cache()
    local choices
    local original_select = vim.ui.select
    vim.ui.select = function(items, _, callback)
      choices = items
      callback(nil)
    end
    require("miniobsidian.note").follow_or_create(assert(wikilink.parse("[[Index]]")))
    vim.ui.select = original_select
    assert.same({ "Areas/Index", "Projects/Index" }, choices)
  end)

  it("creates a missing qualified target in the requested directory", function()
    local original_input = vim.ui.input
    vim.ui.input = function(_, callback)
      callback("")
    end
    require("miniobsidian.note").follow_or_create(assert(wikilink.parse("[[Projects/New Note]]")))
    vim.wait(1000, function()
      return vim.fn.filereadable(vault .. "/Projects/New Note.md") == 1
    end)
    vim.ui.input = original_input
    assert.equals(1, vim.fn.filereadable(vault .. "/Projects/New Note.md"))
  end)

  it("deduplicates internal symlink identities for navigation and scanning", function()
    local real = vault .. "/Notes/Real.md"
    local alias = vault .. "/Notes/Alias.md"
    vim.fn.writefile({ "# Real" }, real)
    assert(vim.uv.fs_symlink(real, alias))
    local core = require("miniobsidian")
    assert.same({ real }, core.get_all_notes(true))
    core.update_note_cache(alias)
    assert.same({ real }, core.get_all_notes())
    local result = assert(wikilink.resolve({ target = "Real" }, { alias, real }, vault))
    assert.equals("Notes/Real", result.id)
    vim.fn.writefile({ "[[Real]]" }, vault .. "/Notes/Ref.md")
    assert.equals(1, #assert(require("miniobsidian.backlinks").collect(real)))
  end)
end)
