local helpers = require("tests.helpers")

local BEFORE = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
local AFTER = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

local function change(path, before_content)
  return {
    path = path,
    revision_before = BEFORE,
    revision_after = AFTER,
    summary = "Agent updated status",
    before_content = before_content,
  }
end

local function result(status, changes, errors)
  return {
    schema_version = "miniobsidian.agent-result/v1",
    request_id = "handoff-update-1",
    status = status,
    summary = "Agent result summary",
    changes = changes or {},
    errors = errors or {},
  }
end

describe("Agent result UX", function()
  local vault
  local path
  local original_select
  local external

  before_each(function()
    original_select = vim.ui.select
    vault = helpers.temp_vault()
    path = vault .. "/Notes/Status.md"
    vim.fn.writefile({ "# Status", "", "Before" }, path)
    helpers.configure(vault)
    external = require("miniobsidian.external_changes")
    require("miniobsidian.handoff").last_request = {
      request_id = "handoff-update-1",
    }
  end)

  after_each(function()
    vim.ui.select = original_select
    external.stop_watcher()
    require("miniobsidian.handoff").last_request = nil
    helpers.cleanup(vault)
  end)

  it("rejects invalid and mismatched result envelopes", function()
    local _, invalid = require("miniobsidian.agent_result").handle({})
    assert.equals("AGENT_RESULT_INVALID", invalid.code)

    local mismatch = result("success")
    mismatch.request_id = "other-request"
    local _, err = require("miniobsidian.agent_result").handle(mismatch)
    assert.equals("AGENT_REQUEST_MISMATCH", err.code)
  end)

  it("renders partial-failure recovery steps without applying anything", function()
    local handled, err = require("miniobsidian.agent_result").handle(result("partial", {}, {
      {
        code = "PARTIAL_FAILURE",
        path = "Notes/Status.md",
        message = "one rewrite failed",
        recovery_steps = { "inspect disk", "retry only failed target" },
      },
    }))
    assert.is_nil(err)
    assert.equals("partial", handled.status)
    local text = table.concat(vim.api.nvim_buf_get_lines(handled.summary_buffer, 0, -1, false), "\n")
    assert.matches("Recovery checklist", text)
    assert.matches("PARTIAL_FAILURE", text)
    assert.matches("retry only failed target", text)
    assert.same({ "# Status", "", "Before" }, vim.fn.readfile(path))
  end)

  it("stops immediately for a cancelled result", function()
    local before = #vim.api.nvim_list_bufs()
    local handled, err = require("miniobsidian.agent_result").handle(result("cancelled"))
    assert.is_nil(err)
    assert.equals("cancelled", handled.status)
    assert.equals(before, #vim.api.nvim_list_bufs())
    assert.same({ "# Status", "", "Before" }, vim.fn.readfile(path))
  end)

  it("offers a changed-files picker for multi-file results", function()
    local choices
    vim.ui.select = function(items, opts, callback)
      choices = items
      assert.matches("changed file", opts.prompt)
      callback(nil)
    end
    local handled = require("miniobsidian.agent_result").handle(result("success", {
      change("Notes/Status.md", "# Status\n\nBefore\n"),
      change("Notes/Other.md", "# Other\n"),
    }))
    assert.equals(2, handled.changed_files)
    assert.equals(2, #choices)
    assert.equals("Notes/Other.md", choices[2].path)
  end)

  it("shows a clean buffer diff and blocks stale writes without auto reload", function()
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local source = vim.api.nvim_get_current_buf()
    vim.fn.writefile({ "# Status", "", "Agent" }, path)
    vim.ui.select = function(items, _, callback)
      assert.same({
        require("miniobsidian.agent_result").actions.diff,
        require("miniobsidian.agent_result").actions.keep,
        require("miniobsidian.agent_result").actions.reload,
      }, items)
      callback(require("miniobsidian.agent_result").actions.keep)
    end
    local inspected, err =
      require("miniobsidian.agent_result").inspect_change(change("Notes/Status.md", "# Status\n\nBefore\n"))
    assert.is_nil(err)
    assert.equals("diff", inspected.kind)
    local diff = table.concat(vim.api.nvim_buf_get_lines(inspected.buffer, 0, -1, false), "\n")
    assert.matches("%-Before", diff)
    assert.matches("%+Agent", diff)
    assert.equals("Before", vim.api.nvim_buf_get_lines(source, 2, 3, false)[1])
    assert.is_false(external.before_write(source))
  end)

  it("opens base, Agent disk, and dirty local versions without choosing for the user", function()
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local source = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(source, 2, 3, false, { "Local" })
    vim.fn.writefile({ "# Status", "", "Agent" }, path)
    vim.ui.select = function(_, _, callback)
      callback(require("miniobsidian.agent_result").actions.keep)
    end
    local inspected, err =
      require("miniobsidian.agent_result").inspect_change(change("Notes/Status.md", "# Status\n\nBefore\n"))
    assert.is_nil(err)
    assert.equals("three_way", inspected.kind)
    assert.matches("Before", table.concat(vim.api.nvim_buf_get_lines(inspected.view.base_buf, 0, -1, false), "\n"))
    assert.matches("Agent", table.concat(vim.api.nvim_buf_get_lines(inspected.view.disk_buf, 0, -1, false), "\n"))
    assert.matches("Local", table.concat(vim.api.nvim_buf_get_lines(inspected.view.local_buf, 0, -1, false), "\n"))
    assert.equals("Local", vim.api.nvim_buf_get_lines(source, 2, 3, false)[1])
    assert.is_true(vim.api.nvim_get_option_value("modified", { buf = source }))
  end)

  it("fails safely when a dirty three-way result lacks base content", function()
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local source = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(source, 2, 3, false, { "Local" })
    vim.fn.writefile({ "# Status", "", "Agent" }, path)
    local missing = change("Notes/Status.md")
    missing.before_content = nil
    local inspected, err = require("miniobsidian.agent_result").inspect_change(missing)
    assert.is_nil(inspected)
    assert.equals("AGENT_BASE_MISSING", err.code)
    assert.equals("Local", vim.api.nvim_buf_get_lines(source, 2, 3, false)[1])
    assert.same({ "# Status", "", "Agent" }, vim.fn.readfile(path))
    assert.is_false(external.before_write(source))
  end)
end)
