local helpers = require("tests.helpers")

describe("local file creation", function()
  local vault

  before_each(function()
    vault = helpers.temp_vault()
  end)

  after_each(function()
    helpers.cleanup(vault)
  end)

  it("creates a new file without replacing an existing target", function()
    local path = vault .. "/Notes/exclusive.md"
    local fs = require("miniobsidian.fs")

    local created, err = fs.create_exclusive(path, "first\n")
    assert.is_nil(err)
    assert.is_true(created)

    created, err = fs.create_exclusive(path, "second\n")
    assert.is_nil(err)
    assert.is_false(created)
    assert.same({ "first" }, vim.fn.readfile(path))
  end)

  it("reports failures without leaving a partial file", function()
    local path = vault .. "/Missing/note.md"
    local created, err = require("miniobsidian.fs").create_exclusive(path, "content")
    assert.is_nil(created)
    assert.truthy(err)
    assert.equals(0, vim.fn.filereadable(path))
  end)

  it("publishes a file without replacing an existing target", function()
    local fs = require("miniobsidian.fs")
    local source = vault .. "/Notes/source.tmp"
    local target = vault .. "/Notes/target.png"
    vim.fn.writefile({ "new" }, source)
    vim.fn.writefile({ "old" }, target)

    local linked, err = fs.link_exclusive(source, target)
    assert.is_false(linked)
    assert.is_nil(err)
    assert.same({ "old" }, vim.fn.readfile(target))
    assert.same({ "new" }, vim.fn.readfile(source))
  end)

  it("publishes a file atomically when the target is absent", function()
    local fs = require("miniobsidian.fs")
    local source = vault .. "/Notes/source.tmp"
    local target = vault .. "/Notes/target.png"
    vim.fn.writefile({ "new" }, source)

    assert.is_true(fs.link_exclusive(source, target))
    assert.same({ "new" }, vim.fn.readfile(target))
  end)
end)
