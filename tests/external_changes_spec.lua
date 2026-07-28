local helpers = require("tests.helpers")

describe("external changes", function()
  local vault
  local path
  local external
  local group
  local buf

  before_each(function()
    vault = helpers.temp_vault()
    helpers.configure(vault)
    path = vault .. "/Notes/Status.md"
    vim.fn.writefile({ "# Status", "", "Initial" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    buf = vim.api.nvim_get_current_buf()
    external = require("miniobsidian.external_changes")
    group = vim.api.nvim_create_augroup("miniobsidian_external_test", { clear = true })
    external.setup_autocmds(group)
  end)

  after_each(function()
    external.stop_watcher()
    pcall(vim.api.nvim_del_augroup_by_id, group)
    helpers.cleanup(vault)
  end)

  local function external_write(lines)
    vim.fn.writefile(lines, path)
    local stat = (vim.uv or vim.loop).fs_stat(path)
    local future = stat.mtime.sec + 2
    (vim.uv or vim.loop).fs_utime(path, future, future)
  end

  it("keeps a modified buffer and blocks a stale write", function()
    vim.api.nvim_buf_set_lines(0, 2, 3, false, { "Changed in Neovim" })
    external_write({ "# Status", "", "Changed on disk" })
    local choices
    local original_select = vim.ui.select
    vim.ui.select = function(items, _, callback)
      choices = items
      callback(external.actions.keep)
    end
    vim.cmd("checktime")
    vim.wait(1000, function()
      return choices ~= nil
    end)
    vim.ui.select = original_select

    assert.same({ external.actions.diff, external.actions.keep, external.actions.reload }, choices)
    assert.equals("Changed in Neovim", vim.api.nvim_buf_get_lines(0, 2, 3, false)[1])
    assert.is_true(vim.api.nvim_get_option_value("modified", { buf = 0 }))
    local ok, err = external.before_write(buf)
    assert.is_false(ok)
    assert.truthy(err:find("外部修改", 1, true))
    local wrote = pcall(vim.cmd, "write")
    assert.is_false(wrote)
    assert.same({ "# Status", "", "Changed on disk" }, vim.fn.readfile(path))
  end)

  it("blocks a stale write without requiring FocusGained or checktime", function()
    vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "Changed in Neovim" })
    external_write({ "# Status", "", "Changed on disk while focused" })

    local original_select = vim.ui.select
    vim.ui.select = function(_, _, callback)
      callback(external.actions.keep)
    end
    local wrote = pcall(vim.cmd, "write")
    vim.ui.select = original_select

    assert.is_false(wrote)
    assert.is_not_nil(external.get_conflict(buf))
    assert.equals("Changed in Neovim", vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1])
    assert.same({ "# Status", "", "Changed on disk while focused" }, vim.fn.readfile(path))
  end)

  it("reloads an unmodified buffer only when explicitly configured", function()
    require("miniobsidian").config.external_change_mode = "reload"
    external_write({ "# Status", "", "Changed on disk" })
    vim.cmd("checktime")
    vim.wait(1000, function()
      return vim.api.nvim_buf_get_lines(0, 2, 3, false)[1] == "Changed on disk"
    end)
    assert.equals("Changed on disk", vim.api.nvim_buf_get_lines(0, 2, 3, false)[1])
    assert.is_false(vim.api.nvim_get_option_value("modified", { buf = 0 }))
  end)

  it("prompts instead of reloading an unmodified buffer by default", function()
    external_write({ "# Status", "", "Changed on disk" })
    local choices
    local original_select = vim.ui.select
    vim.ui.select = function(items, _, callback)
      choices = items
      callback(external.actions.keep)
    end
    vim.cmd("checktime")
    vim.wait(1000, function()
      return choices ~= nil
    end)
    vim.ui.select = original_select

    assert.same({ external.actions.diff, external.actions.keep, external.actions.reload }, choices)
    assert.equals("Initial", vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1])
    assert.is_not_nil(external.get_conflict(buf))
    local ok = external.before_write(buf)
    assert.is_false(ok)
  end)

  it("shows a unified diff while preserving both versions", function()
    vim.api.nvim_buf_set_lines(0, 2, 3, false, { "Changed in Neovim" })
    external_write({ "# Status", "", "Changed on disk" })
    local diff = external.diff(buf)
    assert.truthy(diff:find("-Changed in Neovim", 1, true))
    assert.truthy(diff:find("+Changed on disk", 1, true))
  end)

  it("invalidates the note cache for an external create without scanning on each key", function()
    local core = require("miniobsidian")
    core.get_all_notes(true)
    local before = core.get_cache_stamp()
    vim.fn.writefile({ "# New" }, vault .. "/New.md")
    vim.wait(2000, function()
      return core.get_cache_stamp() > before
    end)
    assert.is_true(core.get_cache_stamp() > before)
    local notes = core.get_all_notes()
    assert.is_true(vim.tbl_contains(notes, vault .. "/New.md"))

    local after_create = core.get_cache_stamp()
    vim.fn.rename(vault .. "/New.md", vault .. "/Renamed.md")
    vim.wait(2000, function()
      return core.get_cache_stamp() > after_create
    end)
    assert.is_true(core.get_cache_stamp() > after_create)

    local after_rename = core.get_cache_stamp()
    vim.fn.delete(vault .. "/Renamed.md")
    vim.wait(2000, function()
      return core.get_cache_stamp() > after_rename
    end)
    assert.is_true(core.get_cache_stamp() > after_rename)
  end)
end)
