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

  it("rejects an escaping templates directory", function()
    require("miniobsidian").config.templates_folder = "../Outside"
    require("miniobsidian.template").new_template("Escape")
    vim.wait(50)
    local path = vim.fn.fnamemodify(vault, ":h") .. "/Outside/Escape.md"
    assert.equals(0, vim.fn.filereadable(path))
  end)

  it("renders common variables case-insensitively and keeps unknown variables", function()
    local timestamp = os.time({ year = 2026, month = 7, day = 24, hour = 9, min = 30, sec = 0 })
    local content, warnings = require("miniobsidian.template").render(
      "{{DATE}} {{time}} {{Title}} {{filename}} {{yesterday}} {{tomorrow}} {{date:YYYY/MM/DD}} {{unknown}}",
      { timestamp = timestamp, title = "Daily", date_format = "%Y-%m-%d" }
    )
    assert.equals("2026-07-24 09:30 Daily Daily 2026-07-23 2026-07-25 2026/07/24 {{unknown}}", content)
    assert.equals(1, #warnings)
  end)

  it("uses relative paths for duplicate template basenames", function()
    vim.fn.mkdir(vault .. "/Templates/Work", "p")
    vim.fn.mkdir(vault .. "/Templates/Home", "p")
    vim.fn.writefile({ "work" }, vault .. "/Templates/Work/Daily.md")
    vim.fn.writefile({ "home" }, vault .. "/Templates/Home/Daily.md")
    local choices
    local original_select = vim.ui.select
    vim.ui.select = function(items, _, callback)
      choices = items
      callback(nil)
    end
    require("miniobsidian.template").insert()
    vim.ui.select = original_select
    assert.same({ "Home/Daily", "Work/Daily" }, choices)
  end)

  it("rejects unsupported Moment tokens", function()
    local content, _, err = require("miniobsidian.template").render("{{date:YYYY-[Q]Qo}}", { title = "Daily" })
    assert.is_nil(content)
    assert.truthy(err:find("不支持", 1, true))
  end)

  it("shifts calendar dates across a DST boundary instead of adding 86400 seconds", function()
    local previous_tz = vim.env.TZ
    vim.env.TZ = "America/New_York"
    local datetime = require("miniobsidian.datetime")
    local before = os.time({ year = 2026, month = 3, day = 7, hour = 12, min = 0, sec = 0 })
    local after = datetime.shift_calendar_day(before, 1)
    assert.equals("2026-03-08", os.date("%Y-%m-%d", after))
    assert.equals(23 * 60 * 60, after - before)
    vim.env.TZ = previous_tz
  end)
end)
