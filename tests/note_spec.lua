local helpers = require("tests.helpers")

describe("note", function()
  local vault

  before_each(function()
    vault = helpers.temp_vault()
    helpers.configure(vault)
  end)

  after_each(function()
    helpers.cleanup(vault)
  end)

  it("creates a note only inside the temporary vault", function()
    require("miniobsidian.note")._create_note("Local Test")
    vim.wait(1000, function()
      return vim.fn.filereadable(vault .. "/Notes/local-test.md") == 1
    end)
    local lines = vim.fn.readfile(vault .. "/Notes/local-test.md")
    assert.equals('title: "Local Test"', lines[2])
    assert.equals("# Local Test", lines[7])
  end)

  it("rejects an escaping notes directory", function()
    require("miniobsidian").config.notes_subdir = "../Outside"
    require("miniobsidian.note")._create_note("Escape")
    vim.wait(50)
    assert.equals(0, vim.fn.filereadable(vim.fn.fnamemodify(vault, ":h") .. "/Outside/escape.md"))
  end)

  it("opens an existing note without replacing its content", function()
    local path = vault .. "/Notes/existing.md"
    vim.fn.writefile({ "keep me" }, path)
    require("miniobsidian.note")._create_note("Existing")
    vim.wait(1000, function()
      return vim.api.nvim_buf_get_name(0) == path
    end)
    assert.same({ "keep me" }, vim.fn.readfile(path))
  end)

  it("uses notes_subdir by default and supports an explicit whole-Vault picker scope", function()
    local captured = {}
    local previous = package.loaded.snacks
    package.loaded.snacks = {
      picker = {
        files = function(opts)
          captured.files = opts
        end,
        grep = function(opts)
          captured.grep = opts
        end,
      },
    }

    local core = require("miniobsidian")
    core.config.picker_scope = "notes"
    require("miniobsidian.note").quick_switch()
    assert.equals(vim.uv.fs_realpath(vault .. "/Notes"), vim.uv.fs_realpath(captured.files.cwd))

    core.config.picker_scope = "vault"
    require("miniobsidian.note").quick_switch()
    require("miniobsidian.note").search("local")
    local real_vault = vim.uv.fs_realpath(vault)
    assert.equals(real_vault, vim.uv.fs_realpath(captured.files.cwd))
    assert.equals(real_vault, vim.uv.fs_realpath(captured.grep.cwd))
    package.loaded.snacks = previous
  end)
end)
