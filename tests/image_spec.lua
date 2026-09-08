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

  it("publishes attachments and inserts escaped Markdown destinations", function()
    helpers.configure(vault)
    local note = vault .. "/Notes/Test.md"
    vim.fn.writefile({ "# Test" }, note)
    vim.cmd("edit " .. vim.fn.fnameescape(note))
    local original_system = vim.system
    local original_has = vim.fn.has
    local previous_image = package.loaded["miniobsidian.image"]
    vim.fn.has = function(feature)
      return feature == "mac" and 1 or original_has(feature)
    end
    package.loaded["miniobsidian.image"] = nil
    local image = require("miniobsidian.image")
    vim.fn.has = original_has
    local ext = "png"
    vim.system = function(args)
      local temporary = args[5] .. "/paste-0." .. ext
      vim.fn.writefile({ "attachment bytes" }, temporary)
      return {
        wait = function()
          return { code = 0, stdout = vim.json.encode({ { temp_path = temporary, ext = ext } }) }
        end,
      }
    end
    local ok, err = pcall(function()
      image.paste_file("a b#c)")
      ext = "pdf"
      image.paste_file("a[b]")
    end)
    vim.system = original_system
    package.loaded["miniobsidian.image"] = previous_image
    assert.is_true(ok, tostring(err))
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    assert.equals("![](../Assets/a%20b%23c%29.png)", lines[2])
    assert.equals("[a\\[b\\].pdf](../Assets/a%5Bb%5D.pdf)", lines[3])
    assert.same({ "attachment bytes" }, vim.fn.readfile(attachments .. "/a b#c).png"))
    assert.same({ "attachment bytes" }, vim.fn.readfile(attachments .. "/a[b].pdf"))
    assert.same({}, vim.fn.globpath(attachments, ".miniobsidian-paste-*", false, true))
  end)
end)
