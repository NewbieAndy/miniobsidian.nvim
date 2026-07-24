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
    assert.equals(parent .. "/A", vaults[1].path)
  end)
end)
