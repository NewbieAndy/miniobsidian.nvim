local helpers = require("tests.helpers")

local compatible_capabilities = vim.json.encode({
  protocol_version = "obs-cli/v2",
  ok = true,
  operation = "capabilities.get",
  request_id = "fake-capabilities",
  data = {
    cli_version = "v2.0.0-rc.1",
    protocol_versions = { "obs-cli/v2" },
    vault_contract = { target = "vault-contract/v1", implemented = "vault-contract/v1" },
    operations = {
      { name = "note.get", version = 1, mutating = false },
      { name = "note.patch", version = 1, mutating = true },
    },
  },
  warnings = {},
})

local success_envelope = vim.json.encode({
  protocol_version = "obs-cli/v2",
  ok = true,
  operation = "note.get",
  request_id = "fake-call",
  data = { echoed = true },
  warnings = {},
})

local function fake_cli(lines)
  local path = vim.fn.tempname()
  vim.fn.writefile(lines, path)
  vim.fn.setfperm(path, "rwx------")
  return path
end

local function normal_fake()
  return fake_cli({
    "#!/bin/sh",
    'if [ "$1" = "capabilities" ]; then',
    ("  printf '%%s\\n' '%s'"):format(compatible_capabilities),
    'elif [ "$1" = "echo-args" ]; then',
    '  record="$2"',
    "  shift 2",
    '  printf \'%s\\n\' "$@" > "$record"',
    ("  printf '%%s\\n' '%s'"):format(success_envelope),
    "else",
    "  exit 9",
    "fi",
  })
end

local function await_refresh(cli)
  local done = false
  local observed
  cli.refresh(function(result)
    observed = result
    done = true
  end)
  assert.is_true(vim.wait(3000, function()
    return done
  end, 10))
  return observed
end

local function await_call(cli, args, opts)
  local done = false
  local result
  local err
  local started = cli.call(args, opts, function(call_result, call_err)
    result = call_result
    err = call_err
    done = true
  end)
  assert.is_true(vim.wait(3000, function()
    return done
  end, 10))
  return started, result, err
end

describe("optional obs-cli adapter", function()
  local vault
  local files

  before_each(function()
    vault = helpers.temp_vault()
    helpers.configure(vault)
    files = {}
  end)

  after_each(function()
    for _, path in ipairs(files) do
      vim.fn.delete(path)
    end
    helpers.cleanup(vault)
  end)

  local function track(path)
    files[#files + 1] = path
    return path
  end

  it("defaults to optional auto mode and does not require an executable", function()
    local core = require("miniobsidian")
    local defaults = core.default_config()
    assert.equals("auto", defaults.cli.enabled)
    assert.equals("obs-cli", defaults.cli.command)

    core.config.cli = {
      enabled = "auto",
      command = "miniobsidian-missing-cli",
      timeout_ms = 20,
    }
    local cli = require("miniobsidian.cli")
    local observed = await_refresh(cli)
    assert.equals("unavailable", observed.status)
    assert.equals("CLI_UNAVAILABLE", observed.error.code)

    vim.fn.writefile({ "# local still works" }, vault .. "/Notes/local.md")
    assert.equals(1, #core.get_all_notes(true))
  end)

  it("caches compatible capabilities and refreshes explicitly", function()
    local command = track(normal_fake())
    local core = require("miniobsidian")
    core.config.cli = { enabled = true, command = command, timeout_ms = 3000 }
    local cli = require("miniobsidian.cli")

    local ready = await_refresh(cli)
    assert.equals("ready", ready.status)
    assert.equals("v2.0.0-rc.1", ready.cli_version)
    assert.is_true(cli.available("note.get"))
    assert.is_true(cli.available("note.patch"))
    assert.is_false(cli.available("note.delete"))

    vim.fn.writefile({ "#!/bin/sh", "printf 'not-json\\n'" }, command)
    vim.fn.setfperm(command, "rwx------")
    assert.equals("ready", cli.state().status)
    assert.equals("error", await_refresh(cli).status)
    assert.equals("CLI_INVALID_JSON", cli.state().error.code)
  end)

  it("passes argv without shell interpolation and parses the JSON envelope", function()
    local command = track(normal_fake())
    local record = track(vim.fn.tempname())
    local sentinel = track(vim.fn.tempname())
    vim.fn.delete(sentinel)
    local payload = "$(touch " .. sentinel .. '); a b; `uname`; "quoted"'

    local core = require("miniobsidian")
    core.config.cli = { enabled = true, command = command, timeout_ms = 3000 }
    local cli = require("miniobsidian.cli")
    assert.equals("ready", await_refresh(cli).status)

    local started, result, err = await_call(cli, { "echo-args", record, payload }, { operation = "note.get" })
    assert.is_true(started)
    assert.is_nil(err)
    assert.equals("note.get", result.operation)
    assert.same({ payload }, vim.fn.readfile(record))
    assert.equals(0, vim.fn.filereadable(sentinel))
  end)

  it("blocks mutation when the advertised protocol is incompatible", function()
    local mutation_marker = track(vim.fn.tempname())
    vim.fn.delete(mutation_marker)
    local incompatible = vim.json.encode({
      protocol_version = "obs-cli/v1",
      ok = true,
      operation = "capabilities.get",
      data = {
        cli_version = "v1.9.9",
        protocol_versions = { "obs-cli/v1" },
        operations = { { name = "note.patch", version = 1, mutating = true } },
      },
    })
    local command = track(fake_cli({
      "#!/bin/sh",
      'if [ "$1" = "capabilities" ]; then',
      ("  printf '%%s\\n' '%s'"):format(incompatible),
      "else",
      ("  touch '%s'"):format(mutation_marker),
      "fi",
    }))

    local core = require("miniobsidian")
    core.config.cli = { enabled = true, command = command, timeout_ms = 3000 }
    local cli = require("miniobsidian.cli")
    local checked = await_refresh(cli)
    assert.equals("incompatible", checked.status)
    assert.equals("CLI_PROTOCOL_INCOMPATIBLE", checked.error.code)

    local started, _, err = await_call(
      cli,
      { "note", "patch", "Demo.md" },
      { operation = "note.patch", mutating = true }
    )
    assert.is_false(started)
    assert.equals("CLI_PROTOCOL_INCOMPATIBLE", err.code)
    assert.equals(0, vim.fn.filereadable(mutation_marker))
  end)

  it("rejects an incompatible Vault contract before exposing operations", function()
    local incompatible = vim.json.decode(compatible_capabilities)
    incompatible.data.vault_contract.implemented = "vault-contract/v0"
    local command = track(fake_cli({
      "#!/bin/sh",
      ("printf '%%s\\n' '%s'"):format(vim.json.encode(incompatible)),
    }))

    local core = require("miniobsidian")
    core.config.cli = { enabled = true, command = command, timeout_ms = 3000 }
    local cli = require("miniobsidian.cli")
    local checked = await_refresh(cli)

    assert.equals("incompatible", checked.status)
    assert.equals("CLI_VAULT_CONTRACT_INCOMPATIBLE", checked.error.code)
    assert.is_false(cli.available("note.get"))
  end)

  it("downgrades safely on timeout and invalid JSON", function()
    local timeout_command = track(fake_cli({
      "#!/bin/sh",
      "sleep 0.2",
      ("printf '%%s\\n' '%s'"):format(compatible_capabilities),
    }))
    local core = require("miniobsidian")
    core.config.cli = { enabled = true, command = timeout_command, timeout_ms = 20 }
    local cli = require("miniobsidian.cli")
    local timed_out = await_refresh(cli)
    assert.equals("error", timed_out.status)
    assert.equals("CLI_TIMEOUT", timed_out.error.code)

    local invalid_command = track(fake_cli({ "#!/bin/sh", "printf 'not-json\\n'" }))
    core.config.cli = { enabled = true, command = invalid_command, timeout_ms = 3000 }
    local invalid = await_refresh(cli)
    assert.equals("error", invalid.status)
    assert.equals("CLI_INVALID_JSON", invalid.error.code)

    vim.fn.writefile({ "# base feature" }, vault .. "/Notes/base.md")
    assert.equals(1, #core.get_all_notes(true))
  end)
end)
