local helpers = require("tests.helpers")
local path = require("miniobsidian.path")

describe("vault path policy", function()
  local vault

  before_each(function()
    vault = helpers.temp_vault()
  end)

  after_each(function()
    helpers.cleanup(vault)
  end)

  it("accepts unicode, spaces, and Windows separators as logical paths", function()
    local result = assert(path.resolve(vault, "知识库\\你好 世界.md"))
    assert.equals("知识库/你好 世界.md", result.logical)
    assert.equals(path.join(path.realpath(vault), "知识库/你好 世界.md"), result.path)
  end)

  it("rejects traversal, absolute, hidden, ADS, and reserved Windows paths", function()
    for _, input in ipairs({
      "../outside.md",
      "/tmp/outside.md",
      "C:\\Windows\\note.md",
      "\\\\server\\share\\note.md",
      ".obsidian/app.json",
      "Notes/name:stream.md",
      "Notes/CON.md",
      "Notes/trailing. ",
    }) do
      local result, err = path.resolve(vault, input)
      assert.is_nil(result, input)
      assert.matches("PATH_OUTSIDE_VAULT", err)
    end
  end)

  it("rejects an escaping attachments folder before any write", function()
    local result, err = path.resolve(vault, "../External Assets/image")
    assert.is_nil(result)
    assert.matches("PATH_OUTSIDE_VAULT", err)
  end)

  it("matches the pinned Windows path fixture", function()
    local fixture = vim.env.MINIOBSIDIAN_ROOT .. "/tests/fixtures/windows-paths.json"
    local cases = vim.json.decode(table.concat(vim.fn.readfile(fixture), "\n"))
    for _, item in ipairs(cases.inputs) do
      local result = path.resolve(vault, item.path)
      assert.equals(item.valid, result ~= nil, item.path)
    end
  end)

  it("accepts an absolute directory only when it is inside the vault", function()
    local inside = path.join(vault, "Notes")
    vim.fn.mkdir(inside, "p")
    assert.is_not_nil(path.resolve(vault, inside, { allow_absolute = true }))
    assert.is_nil(path.resolve(vault, vim.fn.tempname(), { allow_absolute = true }))
  end)

  it("resolves the nearest existing parent for a new target", function()
    local notes = path.join(vault, "Notes")
    vim.fn.mkdir(notes, "p")
    local result = assert(path.resolve(vault, "Notes/New Folder/Local.md"))
    assert.is_false(result.exists)
    assert.equals(path.join(path.realpath(vault), "Notes/New Folder/Local.md"), result.real_path)
  end)

  it("rejects a symlink escape and permits an internal symlink", function()
    local outside = vim.fn.tempname()
    vim.fn.mkdir(outside, "p")
    vim.fn.writefile({ "secret" }, outside .. "/secret.md")
    assert.is_truthy((vim.uv or vim.loop).fs_symlink(outside, vault .. "/Escape", { dir = true }))
    assert.is_truthy((vim.uv or vim.loop).fs_symlink(vault .. "/Notes", vault .. "/Internal", { dir = true }))

    assert.is_nil(path.resolve(vault, "Escape/new.md"))
    assert.is_not_nil(path.resolve(vault, "Internal/new.md"))
    helpers.cleanup(outside)
  end)

  it("keeps similarly-prefixed sibling directories outside", function()
    assert.is_false(path.is_within_vault(vault, vault .. "-outside/note.md"))
  end)
end)
