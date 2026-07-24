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
end)
