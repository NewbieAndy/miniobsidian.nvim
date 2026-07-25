local helpers = require("tests.helpers")

describe("health", function()
  local vault

  before_each(function()
    vault = helpers.temp_vault()
    helpers.configure(vault)
  end)

  after_each(function()
    helpers.cleanup(vault)
  end)

  it("accepts zero-config auto-discovery when the active Vault is valid", function()
    local core = require("miniobsidian")
    core.config.vaults_parent = ""
    core.config.auto_discover = true
    core.config.vault_path = vault
    local status = require("miniobsidian.health").vault_status(core)
    assert.same({ "ok", "ok" }, { status[1].level, status[2].level })
    assert.truthy(status[1].message:find("自动发现", 1, true))
  end)

  it("reports an actionable error when discovery is disabled without a parent", function()
    local core = require("miniobsidian")
    core.config.vaults_parent = ""
    core.config.auto_discover = false
    local status = require("miniobsidian.health").vault_status(core)
    assert.equals("error", status[1].level)
  end)
end)
