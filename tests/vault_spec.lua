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
end)
