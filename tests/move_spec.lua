local helpers = require("tests.helpers")

local REVISION = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
local PLAN_HASH = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

local function shell_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function envelope(operation, data)
  return vim.json.encode({
    protocol_version = "obs-cli/v2",
    ok = true,
    operation = operation,
    request_id = "move-test",
    data = data,
    warnings = {},
  })
end

local function error_envelope(operation, code, message)
  return vim.json.encode({
    protocol_version = "obs-cli/v2",
    ok = false,
    operation = operation,
    request_id = "move-test",
    error = {
      code = code,
      message = message,
      retryable = false,
      details = {},
    },
    warnings = {},
  })
end

local function fake_cli(vault)
  local capabilities = envelope("capabilities.get", {
    cli_version = "v2.0.0-rc.1",
    protocol_versions = { "obs-cli/v2" },
    vault_contract = { target = "vault-contract/v1", implemented = "vault-contract/v1" },
    operations = {
      { name = "note.get", version = 1, mutating = false },
      { name = "note.move", version = 1, mutating = true },
      { name = "note.list", version = 1, mutating = false },
    },
  })
  local get_note = envelope("note.get", {
    note = { path = "Notes/Source.md", revision = REVISION },
  })
  local dry_run = envelope("note.move", {
    plan_hash = PLAN_HASH,
    plan = {
      changes = {
        {
          action = "move",
          target = "Archive/New.md",
          details = {
            expected_revision = REVISION,
            revision_after = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
            link_edits = {
              { before = "[[Notes/Source]]", after = "[[Archive/New]]" },
            },
          },
        },
      },
      risks = {},
    },
  })
  local receipt = envelope("note.move", {
    receipt = {
      source = "Notes/Source.md",
      target = "Archive/New.md",
      plan_hash = PLAN_HASH,
      revision = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    },
  })
  local audit = envelope("note.list", {
    notes = { { path = "Notes/Source.md", revision = REVISION } },
  })
  local target_exists = error_envelope("note.move", "ALREADY_EXISTS", "target note already exists")
  local conflict = error_envelope("note.move", "REVISION_CONFLICT", "source revision changed")
  local script = vim.fn.tempname()
  vim.fn.writefile({
    "#!/bin/sh",
    "vault=" .. shell_quote(vault),
    'if [ "$1" = "capabilities" ]; then',
    ("  printf '%%s\\n' %s"):format(shell_quote(capabilities)),
    'elif [ "$1" = "note" ] && [ "$2" = "get" ]; then',
    ("  printf '%%s\\n' %s"):format(shell_quote(get_note)),
    'elif [ "$1" = "note" ] && [ "$2" = "list" ]; then',
    ("  printf '%%s\\n' %s"):format(shell_quote(audit)),
    'elif [ "$1" = "note" ] && [ "$2" = "move" ]; then',
    '  target="$4"',
    '  case " $* " in',
    '    *" --dry-run "*)',
    '      if [ -e "$vault/$target" ]; then',
    ("        printf '%%s\\n' %s"):format(shell_quote(target_exists)),
    "      else",
    ("        printf '%%s\\n' %s"):format(shell_quote(dry_run)),
    "      fi",
    "      ;;",
    "    *)",
    '      if [ -e "$vault/.conflict" ]; then',
    ("        printf '%%s\\n' %s"):format(shell_quote(conflict)),
    "      else",
    '        mkdir -p "$vault/Archive"',
    '        mv "$vault/Notes/Source.md" "$vault/Archive/New.md"',
    ("        printf '%%s\\n' %s"):format(shell_quote(receipt)),
    "      fi",
    "      ;;",
    "  esac",
    "else",
    "  exit 9",
    "fi",
  }, script)
  vim.fn.setfperm(script, "rwx------")
  return script
end

local function refresh(cli)
  local done = false
  cli.refresh(function()
    done = true
  end)
  assert.is_true(vim.wait(3000, function()
    return done
  end, 10))
  assert.equals("ready", cli.state().status)
end

local function run_move(target, choice)
  local done = false
  local result
  local err
  local old_select = vim.ui.select
  vim.ui.select = function(_, _, callback)
    callback(choice)
  end
  local started = require("miniobsidian.move").move_current(target, {
    on_complete = function(value, failure)
      result = value
      err = failure
      done = true
    end,
  })
  assert.is_true(started)
  assert.is_true(vim.wait(3000, function()
    return done
  end, 10))
  vim.ui.select = old_select
  return result, err
end

describe("safe CLI move workflow", function()
  local vault
  local command
  local original_select

  before_each(function()
    original_select = vim.ui.select
    vault = helpers.temp_vault()
    vim.fn.writefile({ "# Source", "", "body" }, vault .. "/Notes/Source.md")
    helpers.configure(vault)
    command = fake_cli(vault)
    local core = require("miniobsidian")
    core.config.cli = { enabled = true, command = command, timeout_ms = 3000 }
    refresh(require("miniobsidian.cli"))
    vim.cmd("edit " .. vim.fn.fnameescape(vault .. "/Notes/Source.md"))
  end)

  after_each(function()
    vim.ui.select = original_select
    vim.fn.delete(command)
    helpers.cleanup(vault)
  end)

  it("blocks an unsaved buffer before invoking move", function()
    vim.api.nvim_buf_set_lines(0, -1, -1, false, { "changed" })
    local observed
    local started = require("miniobsidian.move").move_current("Archive/New.md", {
      on_complete = function(_, err)
        observed = err
      end,
    })
    assert.is_false(started)
    assert.is_true(vim.wait(1000, function()
      return observed ~= nil
    end, 10))
    assert.equals("UNSAVED_BUFFER", observed.code)
    assert.equals(1, vim.fn.filereadable(vault .. "/Notes/Source.md"))
  end)

  it("keeps the vault unchanged when the user cancels the dry-run", function()
    local result, err = run_move("Archive/New.md", "Cancel")
    assert.is_nil(err)
    assert.equals("cancelled", result.status)
    assert.equals(PLAN_HASH, result.plan_hash)
    assert.equals(1, vim.fn.filereadable(vault .. "/Notes/Source.md"))
    assert.equals(0, vim.fn.filereadable(vault .. "/Archive/New.md"))
  end)

  it("surfaces an existing target with a stable error", function()
    vim.fn.mkdir(vault .. "/Archive", "p")
    vim.fn.writefile({ "# Existing" }, vault .. "/Archive/New.md")
    local _, err = run_move("Archive/New.md", "Apply")
    assert.equals("ALREADY_EXISTS", err.code)
    assert.equals(1, vim.fn.filereadable(vault .. "/Notes/Source.md"))
  end)

  it("applies the authorized plan and synchronizes the current buffer", function()
    local receipt, err = run_move("Archive/New.md", "Apply")
    assert.is_nil(err)
    assert.equals(PLAN_HASH, receipt.plan_hash)
    assert.equals(0, vim.fn.filereadable(vault .. "/Notes/Source.md"))
    assert.equals(1, vim.fn.filereadable(vault .. "/Archive/New.md"))
    assert.equals(vim.uv.fs_realpath(vault .. "/Archive/New.md"), vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)))
    assert.same({ "# Source", "", "body" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it("keeps source and buffer intact on an apply revision conflict", function()
    vim.fn.writefile({ "conflict" }, vault .. "/.conflict")
    local _, err = run_move("Archive/New.md", "Apply")
    assert.equals("REVISION_CONFLICT", err.code)
    assert.equals(1, vim.fn.filereadable(vault .. "/Notes/Source.md"))
    assert.equals(vim.uv.fs_realpath(vault .. "/Notes/Source.md"), vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)))
  end)

  it("opens a readonly audit result without changing vault files", function()
    local done = false
    local result
    assert.is_true(require("miniobsidian.move").audit({
      on_complete = function(value)
        result = value
        done = true
      end,
    }))
    assert.is_true(vim.wait(3000, function()
      return done
    end, 10))
    assert.equals("Notes/Source.md", result.notes[1].path)
    assert.equals("json", vim.bo.filetype)
    assert.is_false(vim.bo.modifiable)
    assert.equals(1, vim.fn.filereadable(vault .. "/Notes/Source.md"))
    assert.equals(0, vim.fn.filereadable(vault .. "/Archive/New.md"))
  end)
end)
