local helpers = require("tests.helpers")

describe("note", function()
  local vault

  before_each(function()
    vault = helpers.temp_vault()
    helpers.configure(vault)
  end)

  after_each(function()
    helpers.cleanup(vault)
  end)

  it("creates a note only inside the temporary vault", function()
    require("miniobsidian.note")._create_note("Agent Test")
    vim.wait(1000, function()
      return vim.fn.filereadable(vault .. "/Notes/agent-test.md") == 1
    end)
    local lines = vim.fn.readfile(vault .. "/Notes/agent-test.md")
    assert.equals('title: "Agent Test"', lines[2])
    assert.equals("# Agent Test", lines[7])
  end)
end)
