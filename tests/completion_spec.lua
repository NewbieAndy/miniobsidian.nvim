local helpers = require("tests.helpers")

describe("wikilink completion", function()
  local vault

  before_each(function()
    vault = helpers.temp_vault()
    helpers.configure(vault)
    vim.fn.mkdir(vault .. "/Areas", "p")
    vim.fn.mkdir(vault .. "/Projects", "p")
    vim.fn.writefile({ "# A" }, vault .. "/Areas/Index.md")
    vim.fn.writefile({ "# B" }, vault .. "/Projects/Index.md")
    require("miniobsidian").invalidate_cache()
  end)

  after_each(function()
    package.loaded["miniobsidian.completion"] = nil
    package.loaded["blink.cmp.types"] = nil
    helpers.cleanup(vault)
  end)

  it("inserts qualified stable targets for duplicate basenames", function()
    package.loaded["blink.cmp.types"] = { CompletionItemKind = { File = 17 } }
    local source = require("miniobsidian.completion").new({})
    local response
    source:get_completions({ line = "[[", cursor = { 1, 2 } }, function(result)
      response = result
    end)
    local inserted = {}
    for _, item in ipairs(response.items) do
      inserted[#inserted + 1] = item.textEdit.newText
    end
    table.sort(inserted)
    assert.same({ "[[Areas/Index]]", "[[Projects/Index]]" }, inserted)
  end)

  it("returns preview read failures outside the libuv fast event", function()
    package.loaded["blink.cmp.types"] = { CompletionItemKind = { File = 17 } }
    local source = require("miniobsidian.completion").new({})
    local resolved
    local in_fast_event

    source:resolve({ _path = vault .. "/missing.md" }, function(item)
      resolved = item
      in_fast_event = vim.in_fast_event()
    end)

    assert.is_true(vim.wait(1000, function()
      return resolved ~= nil
    end))
    assert.is_false(in_fast_event)
    assert.equals(vault .. "/missing.md", resolved._path)
  end)
end)
