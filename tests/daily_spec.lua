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
    assert.equals(0, vim.fn.getfsize(path))
  end)

  it("resets Daily Notes fields to official defaults when config is absent", function()
    local config = require("miniobsidian.config_sync").read_vault_config(vault)
    assert.equals("", config.dailies_folder)
    assert.equals("%Y-%m-%d", config.daily_date_format)
    assert.equals("", config.daily_template)
  end)

  it("rejects an escaping daily directory", function()
    require("miniobsidian").config.dailies_folder = "../Outside"
    require("miniobsidian.daily").open_today()
    vim.wait(50)
    local path = vim.fn.fnamemodify(vault, ":h") .. "/Outside/" .. os.date("%Y-%m-%d") .. ".md"
    assert.equals(0, vim.fn.filereadable(path))
  end)

  it("uses the configured template and preserves an existing note", function()
    vim.fn.mkdir(vault .. "/Templates", "p")
    vim.fn.writefile({ "# {{date}}", "Previous: {{yesterday}}", "Next: {{tomorrow}}" }, vault .. "/Templates/Daily.md")
    local core = require("miniobsidian")
    core.config.daily_template = "Templates/Daily"
    local timestamp = os.time({ year = 2026, month = 7, day = 24, hour = 9, min = 30, sec = 0 })
    require("miniobsidian.daily").open_today({ timestamp = timestamp })
    local path = vault .. "/Dailies/2026-07-24.md"
    vim.wait(1000, function()
      return vim.fn.filereadable(path) == 1
    end)
    assert.same({ "# 2026-07-24", "Previous: 2026-07-23", "Next: 2026-07-25" }, vim.fn.readfile(path))

    vim.fn.writefile({ "keep me" }, path)
    require("miniobsidian.daily").open_today({ timestamp = timestamp })
    vim.wait(50)
    assert.same({ "keep me" }, vim.fn.readfile(path))
  end)

  it("matches the shared daily-template fixture", function()
    local fixture = vim.env.MINIOBSIDIAN_ROOT .. "/tests/fixtures/vault-contract/v1/daily-template"
    local expected = vim.json.decode(table.concat(vim.fn.readfile(fixture .. "/expected.json"), "\n"))
    local config = require("miniobsidian.config_sync").read_vault_config(fixture)
    local core = require("miniobsidian")
    core.config.vault_path = fixture
    core.config.dailies_folder = config.dailies_folder
    core.config.daily_date_format = config.daily_date_format
    core.config.daily_template = config.daily_template
    core.invalidate_cache()

    local timestamp = os.time({ year = 2026, month = 7, day = 24, hour = 9, min = 30, sec = 0 })
    local plan = assert(require("miniobsidian.daily").resolve_today({ timestamp = timestamp }))
    assert.equals(expected.assertions[1].equals, plan.logical)
    assert.truthy(plan.content:find("Previous: " .. expected.assertions[2].yesterday, 1, true))
    assert.truthy(plan.content:find("Next: " .. expected.assertions[2].tomorrow, 1, true))
    assert.truthy(plan.content:find("Custom: " .. expected.assertions[2].custom, 1, true))
    assert.truthy(plan.content:find(expected.assertions[3].preserved, 1, true))
    assert.equals(1, #plan.warnings)
  end)

  it("fails when a configured template is missing or ambiguous", function()
    local core = require("miniobsidian")
    core.config.daily_template = "Missing"
    local plan, err = require("miniobsidian.daily").resolve_today()
    assert.is_nil(plan)
    assert.truthy(err:find("NOTE_NOT_FOUND", 1, true))

    vim.fn.mkdir(vault .. "/Templates/A", "p")
    vim.fn.mkdir(vault .. "/Templates/B", "p")
    vim.fn.writefile({ "A" }, vault .. "/Templates/A/Daily.md")
    vim.fn.writefile({ "B" }, vault .. "/Templates/B/Daily.md")
    core.config.daily_template = "Daily"
    core.invalidate_cache()
    plan, err = require("miniobsidian.daily").resolve_today()
    assert.is_nil(plan)
    assert.truthy(err:find("AMBIGUOUS_NOTE", 1, true))
  end)

  it("opens an existing note even when its former template is unavailable", function()
    local core = require("miniobsidian")
    local date = os.date("%Y-%m-%d")
    vim.fn.mkdir(vault .. "/Dailies", "p")
    vim.fn.writefile({ "existing" }, vault .. "/Dailies/" .. date .. ".md")
    core.config.daily_template = "Templates/Removed"
    require("miniobsidian.daily").open_today()
    vim.wait(1000, function()
      return vim.api.nvim_buf_get_name(0) == vault .. "/Dailies/" .. date .. ".md"
    end)
    assert.same({ "existing" }, vim.fn.readfile(vault .. "/Dailies/" .. date .. ".md"))
  end)
end)
