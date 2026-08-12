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

  it("reads bytes and lines through the shared I/O helpers", function()
    local fs = require("miniobsidian.fs")
    local path = vault .. "/Notes/read.md"
    vim.fn.writefile({ "first", "second" }, path)
    assert.equals("first\nsecond\n", fs.read(path))
    assert.same({ "first", "second" }, fs.read_lines(path))
  end)

  it("atomically replaces complete file content", function()
    local fs = require("miniobsidian.fs")
    local path = vault .. "/Notes/replace.md"
    vim.fn.writefile({ "old" }, path)

    local written, err = fs.write_atomic(path, "new\ncontent\n")

    assert.is_true(written)
    assert.is_nil(err)
    assert.equals("new\ncontent\n", fs.read(path))
    assert.same({}, vim.fn.glob(path .. ".miniobsidian.tmp.*", false, true))
  end)

  it("reports missing reads and safely removes temporary files", function()
    local fs = require("miniobsidian.fs")
    local path = vault .. "/Notes/temp"
    local content, err = fs.read(path)
    assert.is_nil(content)
    assert.truthy(err)
    vim.fn.writefile({ "temp" }, path)
    assert.is_true(fs.unlink(path))
    assert.is_true(fs.unlink(path))
  end)
end)
