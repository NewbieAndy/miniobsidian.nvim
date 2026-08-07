local helpers = require("tests.helpers")

describe("image", function()
  local vault
  local attachments

  before_each(function()
    vault = helpers.temp_vault()
    attachments = vault .. "/Assets"
    vim.fn.mkdir(attachments, "p")
  end)

  after_each(function()
    helpers.cleanup(vault)
  end)

  it("keeps a requested name when no image target exists", function()
    assert.equals("diagram", require("miniobsidian.image").unique_name(attachments, "diagram"))
  end)

  it("increments the suffix without replacing an existing image in any supported format", function()
    vim.fn.writefile({ "png" }, attachments .. "/diagram.png")
    vim.fn.writefile({ "jpg" }, attachments .. "/diagram-1.jpg")
    assert.equals("diagram-2", require("miniobsidian.image").unique_name(attachments, "diagram"))
  end)
end)
