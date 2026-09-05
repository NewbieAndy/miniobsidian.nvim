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
    helpers.cleanup(parent)
  end)

  it("syncs attachments_folder from Obsidian and lets user config win", function()
    local parent = vim.fn.tempname()
    vim.fn.mkdir(parent .. "/Personal/.obsidian", "p")
    vim.fn.writefile({ '{"attachmentFolderPath":"Media"}' }, parent .. "/Personal/.obsidian/app.json")
    local core = require("miniobsidian")

    -- 用户未显式设置时，取 Obsidian 配置
    assert.is_true(core.setup({ vaults_parent = parent, default_vault = "Personal", auto_discover = false }))
    assert.equals("Media", core.config.attachments_folder)

    -- 用户显式设置时，覆盖 Obsidian 配置
    assert.is_true(core.setup({
      vaults_parent = parent,
      default_vault = "Personal",
      auto_discover = false,
      attachments_folder = "MyAssets",
    }))
    assert.equals("MyAssets", core.config.attachments_folder)

    helpers.cleanup(parent)
  end)

  it("rejects invalid enum and Vault-relative path settings", function()
    local core = require("miniobsidian")
    local config = core.default_config()
    config.picker_scope = "somewhere"
    config.notes_subdir = "../outside"
    local errors = core.validate_config(config)
    assert.equals(2, #errors)
  end)

  it("rejects unsafe configuration synchronized during initial setup", function()
    local parent = vim.fn.tempname()
    vim.fn.mkdir(parent .. "/Personal/.obsidian", "p")
    vim.fn.writefile(
      { '{"newFileLocation":"folder","newFileFolderPath":"../Outside"}' },
      parent .. "/Personal/.obsidian/app.json"
    )
    local core = require("miniobsidian")

    local ok, errors = core.setup({ vaults_parent = parent, auto_discover = false })
    assert.is_false(ok)
    assert.equals("", core.active_vault_name)
    assert.equals("", core.config.vault_path)
    assert.truthy(table.concat(errors, "\n"):find("notes_subdir", 1, true))
    helpers.cleanup(parent)
  end)

  it("reports callback failures without propagating them", function()
    local core = helpers.configure(vault)
    local previous_notify = vim.notify
    local notifications = {}
    vim.notify = function(message, level)
      notifications[#notifications + 1] = { message = message, level = level }
    end

    local ok = core.run_callback("after_note_open", function()
      error("callback exploded")
    end)

    vim.notify = previous_notify
    assert.is_false(ok)
    assert.equals(vim.log.levels.WARN, notifications[1].level)
    assert.truthy(notifications[1].message:find("after_note_open callback execution failed", 1, true))
    assert.truthy(notifications[1].message:find("callback exploded", 1, true))
  end)
end)
