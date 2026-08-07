local helpers = require("tests.helpers")

describe("vault", function()
  local parent

  before_each(function()
    parent = vim.fn.tempname()
    vim.fn.mkdir(parent .. "/B/.obsidian", "p")
    vim.fn.mkdir(parent .. "/A/.obsidian", "p")
    vim.fn.mkdir(parent .. "/not-a-vault", "p")
    require("miniobsidian.vault").refresh_vaults()
  end)

  after_each(function()
    helpers.cleanup(parent)
  end)

  it("lists temporary vaults in stable order", function()
    local vaults = require("miniobsidian.vault").list_vaults(parent)
    assert.same({ "A", "B" }, { vaults[1].name, vaults[2].name })
    assert.equals(require("miniobsidian.path").realpath(parent .. "/A"), vaults[1].path)
  end)

  it("does not change cwd by default and uses tab-local cwd when enabled", function()
    local core = require("miniobsidian")
    helpers.configure(parent .. "/A")
    local original = vim.fn.getcwd()
    local global_before = vim.fn.getcwd(-1, -1)

    require("miniobsidian.vault").do_switch({ name = "B", path = parent .. "/B" })
    assert.equals(original, vim.fn.getcwd())
    assert.equals(global_before, vim.fn.getcwd(-1, -1))

    core.config.change_cwd_on_switch = true
    require("miniobsidian.vault").do_switch({ name = "A", path = parent .. "/A" })
    assert.equals(require("miniobsidian.path").realpath(parent .. "/A"), vim.fn.getcwd())
    assert.equals(global_before, vim.fn.getcwd(-1, -1))
    vim.cmd("tcd " .. vim.fn.fnameescape(original))
  end)

  it("rebuilds synchronized folders instead of leaking values across Vaults", function()
    vim.fn.writefile({ '{"newFileLocation":"folder","newFileFolderPath":"Inbox"}' }, parent .. "/A/.obsidian/app.json")
    local core = require("miniobsidian")
    assert.is_true(core.setup({ vaults_parent = parent, auto_discover = false }))
    assert.equals("Inbox", core.config.notes_subdir)

    require("miniobsidian.vault").do_switch({ name = "B", path = parent .. "/B" })
    assert.equals("B", core.active_vault_name)
    assert.equals("Notes", core.config.notes_subdir)
  end)

  it("keeps the previous Vault active when synchronized configuration is unsafe", function()
    vim.fn.writefile(
      { '{"newFileLocation":"folder","newFileFolderPath":"../Outside"}' },
      parent .. "/B/.obsidian/app.json"
    )
    local core = require("miniobsidian")
    assert.is_true(core.setup({ vaults_parent = parent, auto_discover = false }))
    local original_path = core.config.vault_path

    require("miniobsidian.vault").do_switch({ name = "B", path = parent .. "/B" })
    assert.equals("A", core.active_vault_name)
    assert.equals(original_path, core.config.vault_path)
    assert.equals("Notes", core.config.notes_subdir)
  end)

  it("filters stale entries returned by Obsidian auto-discovery", function()
    local vault_module = require("miniobsidian.vault")
    local previous = package.loaded["miniobsidian.config_sync"]
    package.loaded["miniobsidian.config_sync"] = {
      discover_vaults = function()
        return { { name = "Missing", path = parent .. "/Missing" } }
      end,
    }
    require("miniobsidian").config.auto_discover = true
    vault_module.refresh_vaults()

    assert.same({}, vault_module.list_vaults(""))

    package.loaded["miniobsidian.config_sync"] = previous
    vault_module.refresh_vaults()
  end)
end)
