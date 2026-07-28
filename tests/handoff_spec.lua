local helpers = require("tests.helpers")

local REVISION = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

local function envelope(operation, data)
  return vim.json.encode({
    protocol_version = "obs-cli/v1",
    ok = true,
    operation = operation,
    request_id = "handoff-test",
    data = data,
    warnings = {},
  })
end

local function fake_cli()
  local capabilities = envelope("capabilities.get", {
    cli_version = "v1.0.0-rc.1",
    protocol_versions = { "obs-cli/v1" },
    vault_contract = { target = "vault-contract/v1", implemented = "vault-contract/v1" },
    operations = {
      { name = "note.get", version = 1, mutating = false },
      { name = "note.patch", version = 1, mutating = true },
    },
  })
  local snapshot = envelope("note.get", {
    vault = { id = "vault-test" },
    note = {
      path = "Notes/Source.md",
      revision = REVISION,
    },
  })
  local script = vim.fn.tempname()
  vim.fn.writefile({
    "#!/bin/sh",
    'if [ "$1" = "capabilities" ]; then',
    ("  printf '%%s\\n' '%s'"):format(capabilities),
    'elif [ "$1" = "note" ] && [ "$2" = "get" ]; then',
    ("  printf '%%s\\n' '%s'"):format(snapshot),
    "else",
    "  exit 9",
    "fi",
  }, script)
  vim.fn.setfperm(script, "rwx------")
  return script
end

local function refresh()
  local done = false
  local cli = require("miniobsidian.cli")
  cli.refresh(function()
    done = true
  end)
  assert.is_true(vim.wait(3000, function()
    return done
  end, 10))
  assert.equals("ready", cli.state().status)
end

local function run(mode, intent, command_opts)
  local done = false
  local result
  local err
  local started = require("miniobsidian.handoff").handoff(mode, intent, command_opts, {
    on_complete = function(value, failure)
      result = value
      err = failure
      done = true
    end,
  })
  assert.is_true(vim.wait(3000, function()
    return done
  end, 10))
  return result, err, started
end

describe("Agent handoff", function()
  local vault
  local command
  local original_select

  before_each(function()
    original_select = vim.ui.select
    vault = helpers.temp_vault()
    vim.fn.writefile({ "# Source", "public", "secret" }, vault .. "/Notes/Source.md")
    helpers.configure(vault)
    command = fake_cli()
    local core = require("miniobsidian")
    core.config.cli = { enabled = true, command = command, timeout_ms = 3000 }
    refresh()
    vim.cmd("edit " .. vim.fn.fnameescape(vault .. "/Notes/Source.md"))
  end)

  after_each(function()
    vim.ui.select = original_select
    vim.fn.delete(command)
    helpers.cleanup(vault)
  end)

  it("dispatches a bounded readonly payload with Vault ID, path, and revision", function()
    local observed
    require("miniobsidian").config.agent.handler = function(payload)
      observed = payload
      return { queue = "analysis" }
    end
    local result, err = run("analyze", "summarize this note", { range = 0 })
    assert.is_nil(err)
    assert.equals("dispatched", result.status)
    assert.matches("^handoff%-analyze%-", result.request_id)
    assert.equals("miniobsidian.agent-handoff/v1", observed.schema_version)
    assert.equals("vault-test", observed.vault.id)
    assert.equals("Notes/Source.md", observed.source.path)
    assert.equals(REVISION, observed.source.revision)
    assert.equals("none", observed.context.scope)
    assert.same({ "Notes/Source.md" }, observed.permissions.read_paths)
    assert.same({}, observed.permissions.write_paths)
    assert.is_false(observed.permissions.allow_vault_scan)
    assert.equals("obsidian-knowledge-synthesis", observed.agent.skill)
  end)

  it("previews content and leaves the Agent untouched when the user cancels", function()
    local called = false
    require("miniobsidian").config.agent.handler = function()
      called = true
    end
    vim.ui.select = function(_, _, callback)
      callback("Cancel")
    end
    local result, err = run("analyze", "inspect selection", { range = 2, line1 = 2, line2 = 3 })
    assert.is_nil(err)
    assert.equals("cancelled", result.status)
    assert.is_false(called)
  end)

  it("allows a dirty buffer only as confirmed readonly memory context", function()
    vim.api.nvim_buf_set_lines(0, 1, 2, false, { "unsaved" })
    local observed
    require("miniobsidian").config.agent.handler = function(payload)
      observed = payload
    end
    vim.ui.select = function(_, _, callback)
      callback("Send")
    end
    local result, err = run("analyze", "review unsaved draft", { range = 0 })
    assert.is_nil(err)
    assert.equals("dispatched", result.status)
    assert.is_true(observed.source.buffer_modified)
    assert.equals("buffer", observed.context.scope)
    assert.matches("unsaved", observed.context.text)
    assert.same({}, observed.permissions.write_paths)
  end)

  it("blocks update handoff while the current buffer is dirty", function()
    vim.api.nvim_buf_set_lines(0, 1, 2, false, { "unsaved" })
    local called = false
    require("miniobsidian").config.agent.handler = function()
      called = true
    end
    local result, err, started = run("update", "rewrite selection safely", { range = 2, line1 = 2, line2 = 2 })
    assert.is_false(started)
    assert.is_nil(result)
    assert.equals("UNSAVED_BUFFER", err.code)
    assert.is_false(called)
  end)

  it("restricts update permission to the current note and selects the safe update Skill", function()
    local observed
    require("miniobsidian").config.agent.handler = function(payload)
      observed = payload
    end
    vim.ui.select = function(_, _, callback)
      callback("Send")
    end
    local result, err = run("update", "make this sentence concise", { range = 2, line1 = 2, line2 = 2 })
    assert.is_nil(err)
    assert.equals("dispatched", result.status)
    assert.equals("selection", observed.context.scope)
    assert.equals("public", observed.context.text)
    assert.same({ "Notes/Source.md" }, observed.permissions.write_paths)
    assert.equals("obsidian-safe-note-update", observed.agent.skill)
    assert.same({ "note.get", "note.patch" }, observed.agent.required_capabilities)
  end)

  it("fails clearly when no Agent handler is configured", function()
    local _, err = run("analyze", "summarize", { range = 0 })
    assert.equals("AGENT_HANDLER_UNAVAILABLE", err.code)
  end)

  it("forces confirmation for a large selection even when normal confirmation is disabled", function()
    local core = require("miniobsidian")
    core.config.agent.confirm_content = false
    core.config.agent.large_selection_lines = 2
    local called = false
    local prompted = false
    core.config.agent.handler = function()
      called = true
    end
    vim.ui.select = function(_, _, callback)
      prompted = true
      callback("Cancel")
    end
    local result = run("analyze", "inspect selection", { range = 2, line1 = 1, line2 = 3 })
    assert.equals("cancelled", result.status)
    assert.is_true(prompted)
    assert.is_false(called)
  end)
end)
