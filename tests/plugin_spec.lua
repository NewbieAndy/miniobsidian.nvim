local helpers = require("tests.helpers")

describe("plugin entry", function()
  local vault

  before_each(function()
    vault = helpers.temp_vault()
    helpers.configure(vault)
    if vim.fn.exists(":ObsidianNew") == 0 then
      vim.g.loaded_miniobsidian = nil
      dofile(vim.env.MINIOBSIDIAN_ROOT .. "/plugin/miniobsidian.lua")
    end
  end)

  after_each(function()
    package.loaded["miniobsidian.note"] = nil
    helpers.cleanup(vault)
  end)

  it("registers every documented user command", function()
    for _, command in ipairs({
      "ObsidianNew",
      "ObsidianNewHere",
      "ObsidianSwitchVault",
      "ObsidianSwitch",
      "ObsidianSearch",
      "ObsidianBacklinks",
      "ObsidianMove",
      "ObsidianRename",
      "ObsidianTemplate",
      "ObsidianNewTemplate",
      "ObsidianPasteFile",
      "ObsidianToday",
      "ObsidianSetup",
    }) do
      assert.equals(2, vim.fn.exists(":" .. command), command)
    end
  end)

  it("passes command title and bang to the note facade", function()
    local captured
    package.loaded["miniobsidian.note"] = {
      new_note = function(title, opts)
        captured = { title = title, switch_root = opts.switch_root }
      end,
    }
    vim.cmd("ObsidianNew! Example")
    assert.same({ title = "Example", switch_root = true }, captured)
  end)

  it("passes the move destination to the note facade", function()
    local captured
    package.loaded["miniobsidian.note"] = {
      move = function(destination)
        captured = destination
      end,
    }
    vim.cmd("ObsidianMove Archive")
    assert.equals("Archive", captured)
  end)

  it("passes the new filename to the note facade", function()
    local captured
    package.loaded["miniobsidian.note"] = {
      rename = function(name)
        captured = name
      end,
    }
    vim.cmd("ObsidianRename New Name")
    assert.equals("New Name", captured)
  end)

  it("opens backlinks through the note facade", function()
    local called = false
    package.loaded["miniobsidian.note"] = {
      backlinks = function()
        called = true
      end,
    }
    vim.cmd("ObsidianBacklinks")
    assert.is_true(called)
  end)

  it("registers buffer autocmds and updates the written note incrementally", function()
    local core = require("miniobsidian")
    vim.api.nvim_exec_autocmds("User", { pattern = "MiniObsidianSetup" })
    local autocmds = vim.api.nvim_get_autocmds({ group = "miniobsidian_buffers" })
    assert.equals(2, #autocmds)

    local path = vault .. "/Notes/written.md"
    vim.fn.writefile({ "written" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local updated
    local original_update = core.update_note_cache
    core.update_note_cache = function(value)
      updated = value
    end
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = 0 })
    core.update_note_cache = original_update
    assert.equals(vim.uv.fs_realpath(path), vim.uv.fs_realpath(updated))
  end)
end)
