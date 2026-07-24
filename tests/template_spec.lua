local helpers = require("tests.helpers")

describe("template", function()
  local vault

  before_each(function()
    vault = helpers.temp_vault()
    helpers.configure(vault)
  end)

  after_each(function()
    helpers.cleanup(vault)
  end)

  it("creates a template without touching a personal Vault", function()
    require("miniobsidian.template").new_template("Project")
    local path = vault .. "/Templates/Project.md"
    vim.wait(1000, function()
      return vim.fn.filereadable(path) == 1
    end)
    assert.equals("title: {{title}}", vim.fn.readfile(path)[2])
  end)
end)
