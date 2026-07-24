local helpers = require("tests.helpers")

describe("daily", function()
  local vault

  before_each(function()
    vault = helpers.temp_vault()
    helpers.configure(vault)
  end)

  after_each(function()
    helpers.cleanup(vault)
  end)

  it("creates today's note in the temporary vault", function()
    require("miniobsidian.daily").open_today()
    local date = os.date("%Y-%m-%d")
    local path = vault .. "/Dailies/" .. date .. ".md"
    vim.wait(1000, function()
      return vim.fn.filereadable(path) == 1
    end)
    assert.equals("# " .. date, vim.fn.readfile(path)[7])
  end)

  it("rejects an escaping daily directory", function()
    require("miniobsidian").config.dailies_folder = "../Outside"
    require("miniobsidian.daily").open_today()
    vim.wait(50)
    local path = vim.fn.fnamemodify(vault, ":h") .. "/Outside/" .. os.date("%Y-%m-%d") .. ".md"
    assert.equals(0, vim.fn.filereadable(path))
  end)
end)
