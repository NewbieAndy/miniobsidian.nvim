local markdown = require("miniobsidian.markdown")

local function links(content)
  local found = {}
  local rewritten = markdown.transform(content, function(line, visible, number)
    markdown.wikilinks(line, visible, function(inner, column)
      found[#found + 1] = { inner, number, column }
    end)
  end)
  assert.equals(content, rewritten)
  return found
end

describe("Markdown scanning", function()
  it("requires matching fence type, sufficient length and an empty closing suffix", function()
    assert.same(
      { { "real", 9, 0 } },
      links(table.concat({
        "````markdown",
        "```",
        "[[hidden]]",
        "~~~~",
        "[[hidden]]",
        "```` nope",
        "[[hidden]]",
        "`````",
        "[[real]]",
      }, "\r\n"))
    )
    assert.same({ { "real", 5, 0 } }, links("~~~~\n~~~\n[[hidden]]\n~~~~\n[[real]]"))
  end)

  it("ignores comments, indented code and escaped openers while preserving byte positions", function()
    assert.same(
      { { "real", 5, 7 } },
      links("%%\n```\n[[hidden]]\n%%\n中文 [[real]]\n    [[hidden]]\n\\[[hidden]]\n<!-- [[hidden]] -->")
    )
  end)

  it("matches exact inline code delimiters across lines and keeps unmatched ticks literal", function()
    assert.same(
      { { "real", 3, 3 }, { "literal", 4, 2 } },
      links("``code ` [[hidden]]\n[[hidden]]\n`` [[real]]\n` [[literal]]")
    )
  end)

  it("does not let unmatched ticks hide links in later paragraphs", function()
    assert.same({ { "real", 3, 0 } }, links("unmatched `\n\n[[real]] `"))
  end)

  it("keeps nested list links visible and protects code in list and quote containers", function()
    assert.same(
      { { "nested", 2, 6 }, { "continued", 3, 6 }, { "real", 9, 0 } },
      links(table.concat({
        "- parent",
        "    - [[nested]]",
        "      [[continued]]",
        "      ````",
        "      ```",
        "      [[hidden]]",
        "      ````",
        "",
        "[[real]]",
        "> ````",
        "> ```",
        "> [[hidden]]",
        "> ````",
      }, "\n"))
    )
  end)
end)
