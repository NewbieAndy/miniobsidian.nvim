local helpers = require("tests.helpers")
local links = require("miniobsidian.markdown_link")

describe("Markdown destinations", function()
  local vault
  before_each(function()
    vault = helpers.temp_vault()
    vim.fn.mkdir(vault .. "/Assets", "p")
    vim.fn.mkdir(vault .. "/Archive/Deep", "p")
  end)
  after_each(function()
    helpers.cleanup(vault)
  end)

  it("encodes filename characters without encoding directory separators", function()
    assert.equals("../Assets/a%20b%23c%29%25.png", links.encode_path("../Assets/a b#c)%.png"))
    assert.equals("a\\[b\\]\\\\c.pdf", links.escape_label("a[b]\\c.pdf"))
  end)

  it("rebases inline and reference destinations while preserving titles and fragments", function()
    local before = table.concat({
      '![](../Assets/a%20b%23c%29.png "preview")',
      "[document](../Notes/Other.md#Section)",
      "[angle](<../Assets/a b.png>)",
      "[balanced](../Assets/a(b).png)",
      '[ref]: ../Assets/file.pdf "Title"',
      "[label][ref]",
    }, "\r\n")
    local after, count = links.rebase(before, vault .. "/Notes", vault .. "/Archive/Deep", vault)
    assert.equals(
      table.concat({
        '![](../../Assets/a%20b%23c%29.png "preview")',
        "[document](../../Notes/Other.md#Section)",
        "[angle](<../../Assets/a%20b.png>)",
        "[balanced](../../Assets/a%28b%29.png)",
        '[ref]: ../../Assets/file.pdf "Title"',
        "[label][ref]",
      }, "\r\n"),
      after
    )
    assert.equals(5, count)
  end)

  it("preserves external destinations, code, comments and anchors", function()
    local content = table.concat({
      "[web](https://example.com/a)",
      "[mail](mailto:a@example.com)",
      "[absolute](/Assets/file.png)",
      "[anchor](#Section)",
      "[outside](../../outside.png)",
      "`![](../Assets/file.png)`",
      "%% ![](../Assets/file.png) %%",
      "<!-- ![](../Assets/file.png) -->",
      "````md",
      "```",
      "![](../Assets/file.png)",
      "````",
      "[[Notes/Other]]",
      "\\[escaped](../Assets/file.png)",
    }, "\n")
    local after, count = links.rebase(content, vault .. "/Notes", vault .. "/Archive/Deep", vault)
    assert.equals(content, after)
    assert.equals(0, count)
    assert.equals(content, links.rebase(content, vault .. "/Notes", vault .. "/Notes", vault))
  end)
end)
