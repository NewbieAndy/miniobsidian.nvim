local helpers = require("tests.helpers")

describe("explorer adapters", function()
  local vault
  local loaded_names = { "snacks", "neo-tree.sources.manager", "nvim-tree.api", "oil" }

  before_each(function()
    vault = helpers.temp_vault()
    vim.fn.mkdir(vault .. "/Notes/Sub", "p")
    vim.cmd("enew!")
    for _, name in ipairs(loaded_names) do
      package.loaded[name] = nil
    end
  end)

  after_each(function()
    for _, name in ipairs(loaded_names) do
      package.loaded[name] = nil
    end
    helpers.cleanup(vault)
  end)

  it("reads the selected snacks explorer directory", function()
    local win = vim.api.nvim_get_current_win()
    package.loaded.snacks = {
      picker = {
        get = function()
          return {
            {
              list = { win = { win = win } },
              selected = function()
                return { { file = vault .. "/Notes/Sub" } }
              end,
            },
          }
        end,
      },
    }
    assert.equals(vault .. "/Notes/Sub", require("miniobsidian.explorer").current_dir())
  end)

  it("reads neo-tree file parents", function()
    vim.bo.filetype = "neo-tree"
    package.loaded["neo-tree.sources.manager"] = {
      get_state = function()
        return {
          tree = {
            get_node = function()
              return { type = "file", path = vault .. "/Notes/a.md" }
            end,
          },
        }
      end,
    }
    assert.equals(vault .. "/Notes", require("miniobsidian.explorer").current_dir())
  end)

  it("reads nvim-tree directories", function()
    vim.bo.filetype = "NvimTree"
    package.loaded["nvim-tree.api"] = {
      tree = {
        get_node_under_cursor = function()
          return { type = "directory", absolute_path = vault .. "/Notes" }
        end,
      },
    }
    assert.equals(vault .. "/Notes", require("miniobsidian.explorer").current_dir())
  end)

  it("reads oil child directories", function()
    vim.bo.filetype = "oil"
    package.loaded.oil = {
      get_current_dir = function()
        return vault .. "/Notes/"
      end,
      get_cursor_entry = function()
        return { type = "directory", name = "Sub" }
      end,
    }
    assert.equals(vault .. "/Notes/Sub", require("miniobsidian.explorer").current_dir())
  end)

  it("falls back to the netrw current directory", function()
    vim.bo.filetype = "netrw"
    vim.b.netrw_curdir = vault .. "/Notes"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
    assert.equals(vault .. "/Notes", require("miniobsidian.explorer").current_dir())
  end)
end)
