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
end)
