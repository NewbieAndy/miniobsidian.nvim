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
    assert.equals(configured, core.config.vault_path)
    assert.equals("Personal", core.active_vault_name)
    helpers.cleanup(parent)
  end)
end)
