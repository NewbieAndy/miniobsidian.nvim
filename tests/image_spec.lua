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

  describe("unique_filename", function()
    it("keeps the requested filename when no target exists", function()
      assert.equals("diagram.png", require("miniobsidian.image").unique_filename(attachments, "diagram.png"))
    end)

    it("increments the suffix when the same filename exists", function()
      vim.fn.writefile({ "png" }, attachments .. "/diagram.png")
      assert.equals("diagram-1.png", require("miniobsidian.image").unique_filename(attachments, "diagram.png"))
    end)

    it("allows different extensions to coexist", function()
      vim.fn.writefile({ "png" }, attachments .. "/diagram.png")
      assert.equals("diagram.jpg", require("miniobsidian.image").unique_filename(attachments, "diagram.jpg"))
    end)

    it("handles filenames without an extension", function()
      vim.fn.writefile({ "data" }, attachments .. "/README")
      assert.equals("README-1", require("miniobsidian.image").unique_filename(attachments, "README"))
    end)
  end)
end)
