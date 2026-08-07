local helpers = require("tests.helpers")

describe("note cache", function()
  local vault

  before_each(function()
    vault = helpers.temp_vault()
    helpers.configure(vault)
    vim.fn.writefile({ "one" }, vault .. "/Notes/one.md")
    require("miniobsidian").get_all_notes(true)
  end)

  after_each(function()
    helpers.cleanup(vault)
  end)

  it("adds a new note incrementally without another glob scan", function()
    local core = require("miniobsidian")
    local added = vault .. "/Notes/two.md"
    vim.fn.writefile({ "two" }, added)
    local original_globpath = vim.fn.globpath
    vim.fn.globpath = function()
      error("unexpected full scan")
    end

    core.update_note_cache(added)
    local notes = core.get_all_notes()

    vim.fn.globpath = original_globpath
    assert.same({ vault .. "/Notes/one.md", added }, notes)
  end)

  it("removes a deleted note incrementally", function()
    local core = require("miniobsidian")
    local removed = vault .. "/Notes/one.md"
    vim.fn.delete(removed)
    core.update_note_cache(removed)
    assert.same({}, core.get_all_notes())
  end)

  it("ignores paths outside the vault", function()
    local core = require("miniobsidian")
    local outside = vim.fn.tempname() .. ".md"
    vim.fn.writefile({ "outside" }, outside)

    core.update_note_cache(outside)

    assert.same({ vault .. "/Notes/one.md" }, core.get_all_notes())
    vim.fn.delete(outside)
  end)
end)
