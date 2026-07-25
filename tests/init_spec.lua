local helpers = require("tests.helpers")

describe("miniobsidian init", function()
  local vault

  before_each(function()
    vault = helpers.temp_vault()
  end)

  after_each(function()
    helpers.cleanup(vault)
  end)

  it("requires and exposes deterministic helpers", function()
    local core = helpers.configure(vault)
    assert.equals('"a\\\\b\\"c"', core.yaml_quote('a\\b"c'))
    assert.equals("demo", core.note_stem(vault .. "/demo.md"))
    assert.is_true(core.in_vault(vault .. "/Notes/demo.md"))
    assert.is_false(core.in_vault(vault .. "-outside/demo.md"))
  end)

  it("setup selects only the configured temporary vault", function()
    local parent = vim.fn.tempname()
    local configured = parent .. "/Personal"
    vim.fn.mkdir(configured .. "/.obsidian", "p")
    local core = require("miniobsidian")
    core.setup({
      vaults_parent = parent,
      default_vault = "Personal",
      auto_discover = false,
      sync_obsidian_config = false,
    })
    assert.equals(require("miniobsidian.path").realpath(configured), core.config.vault_path)
    assert.equals("Personal", core.active_vault_name)
    helpers.cleanup(parent)
  end)

  it("rebuilds configuration from defaults on every setup", function()
    local parent = vim.fn.tempname()
    vim.fn.mkdir(parent .. "/Personal/.obsidian", "p")
    local core = require("miniobsidian")
    assert.is_true(core.setup({
      vaults_parent = parent,
      auto_discover = false,
      sync_obsidian_config = false,
      notes_subdir = "Custom",
      picker_scope = "vault",
      change_cwd_on_switch = true,
    }))
    assert.equals("Custom", core.config.notes_subdir)

    assert.is_true(core.setup({
      vaults_parent = parent,
      auto_discover = false,
      sync_obsidian_config = false,
    }))
    assert.equals("Notes", core.config.notes_subdir)
    assert.equals("notes", core.config.picker_scope)
    assert.is_false(core.config.change_cwd_on_switch)
    assert.equals("auto", core.config.cli.enabled)
    assert.equals("obs-cli", core.config.cli.command)
    assert.is_nil(core.config.agent.handler)
    assert.is_true(core.config.agent.confirm_content)
    assert.equals(200, core.config.agent.large_selection_lines)
    helpers.cleanup(parent)
  end)

  it("rejects invalid enum, interval, and Vault-relative path settings", function()
    local core = require("miniobsidian")
    local config = core.default_config()
    config.picker_scope = "somewhere"
    config.external_check_interval_ms = -1
    config.notes_subdir = "../outside"
    config.cli.enabled = "sometimes"
    config.agent.handler = "shell command"
    config.agent.confirm_content = "yes"
    config.agent.large_selection_lines = 0
    local errors = core.validate_config(config)
    assert.equals(7, #errors)
  end)
end)
