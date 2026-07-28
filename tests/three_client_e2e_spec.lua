if vim.env.THREE_CLIENT_E2E ~= "1" then
  return
end

local helpers = require("tests.helpers")

local vault_input = assert(vim.env.THREE_CLIENT_VAULT, "THREE_CLIENT_VAULT is required")
local vault = assert((vim.uv or vim.loop).fs_realpath(vault_input), "THREE_CLIENT_VAULT must exist")
local cli_bin = assert(vim.env.THREE_CLIENT_CLI, "THREE_CLIENT_CLI is required")
local workdir = assert(vim.env.THREE_CLIENT_WORKDIR, "THREE_CLIENT_WORKDIR is required")
local summary_path = assert(vim.env.THREE_CLIENT_SUMMARY, "THREE_CLIENT_SUMMARY is required")

local function write(path, content)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local file = assert(io.open(path, "w"))
  file:write(content)
  file:close()
end

local function read(path)
  local file = assert(io.open(path, "r"))
  local content = file:read("*a")
  file:close()
  return content
end

local input_index = 0
local function input_file(content)
  input_index = input_index + 1
  local path = ("%s/input-%02d.md"):format(workdir, input_index)
  write(path, content)
  return path
end

local function cli(args, expected_code)
  local argv = { cli_bin }
  vim.list_extend(argv, args)
  local process = vim.system(argv, { text = true }):wait()
  assert.equals(expected_code or 0, process.code, process.stderr)
  local ok, envelope = pcall(vim.json.decode, process.stdout or "")
  assert.is_true(ok, process.stdout)
  assert.equals("obs-cli/v1", envelope.protocol_version)
  return envelope
end

local function snapshot(path)
  local envelope = cli({ "note", "get", path, "--vault", vault, "--output", "json" })
  assert.is_true(envelope.ok)
  return envelope.data.note
end

local function reset_buffers()
  vim.cmd("silent! %bwipeout!")
end

local function refresh_cli()
  local done = false
  local result
  local err
  require("miniobsidian.cli").refresh(function(value, failure)
    result = value
    err = failure
    done = true
  end)
  assert.is_true(vim.wait(5000, function()
    return done
  end, 10))
  assert.is_nil(err)
  assert.equals("ready", result.status)
end

describe("Obsidian + Agent CLI + miniobsidian E2E", function()
  local original_select

  before_each(function()
    original_select = vim.ui.select
    local core = helpers.configure(vault)
    core.config.watch_external_changes = false
    core.config.cli = { enabled = true, command = cli_bin, timeout_ms = 5000 }
    refresh_cli()
  end)

  after_each(function()
    vim.ui.select = original_select
    require("miniobsidian.external_changes").stop_watcher()
    reset_buffers()
  end)

  it("closes all six three-client scenarios", function()
    -- A: Obsidian-compatible bytes -> Agent search/organize -> Neovim read.
    local search = cli({ "search", "content", "Agent inbox marker", "--vault", vault, "--output", "json" })
    assert.equals(1, search.data.search.total_results)
    assert.equals("Inbox/Obsidian.md", search.data.search.results[1].path)
    local inbox = snapshot("Inbox/Obsidian.md")
    local patch = cli({
      "note",
      "patch",
      "Inbox/Obsidian.md",
      "--match-file",
      input_file("Agent inbox marker."),
      "--content-file",
      input_file("Agent organized marker."),
      "--if-match",
      inbox.revision,
      "--vault",
      vault,
      "--output",
      "json",
    })
    assert.is_true(patch.data.note.changed)
    reset_buffers()
    vim.cmd("edit " .. vim.fn.fnameescape(vault .. "/Inbox/Obsidian.md"))
    assert.matches("Agent organized marker", table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"))
    local organized = snapshot("Inbox/Obsidian.md")
    assert.equals("Obsidian Inbox", organized.frontmatter.title)
    assert.equals("inbox", organized.frontmatter.tags[1])

    -- B: Neovim creates a project note -> Agent performs a revision-guarded status update.
    reset_buffers()
    require("miniobsidian.note").new_note("Project E2E", { note_id = "project-e2e" })
    local project_path = vault .. "/Notes/project-e2e.md"
    assert.is_true(vim.wait(3000, function()
      return vim.fn.filereadable(project_path) == 1
    end, 10))
    local project = snapshot("Notes/project-e2e.md")
    local append = cli({
      "note",
      "append",
      "Notes/project-e2e.md",
      "--content-file",
      input_file("\n## Status\n\n- Progress: verified\n"),
      "--if-match",
      project.revision,
      "--vault",
      vault,
      "--output",
      "json",
    })
    assert.is_true(append.data.note.changed)
    assert.matches("Progress: verified", read(project_path))

    -- C: Agent dry-run -> external edit -> stale apply must fail without overwriting.
    local conflict = snapshot("Conflict.md")
    local match_path = input_file("Agent plan base.")
    local replacement_path = input_file("Agent planned replacement.")
    local dry_run = cli({
      "note",
      "patch",
      "Conflict.md",
      "--match-file",
      match_path,
      "--content-file",
      replacement_path,
      "--if-match",
      conflict.revision,
      "--dry-run",
      "--vault",
      vault,
      "--output",
      "json",
    })
    assert.is_true(dry_run.data.dry_run)
    write(vault .. "/Conflict.md", "# Conflict\n\nExternal edit wins.\n")
    local stale = cli({
      "note",
      "patch",
      "Conflict.md",
      "--match-file",
      match_path,
      "--content-file",
      replacement_path,
      "--if-match",
      conflict.revision,
      "--vault",
      vault,
      "--output",
      "json",
    }, 4)
    assert.is_false(stale.ok)
    assert.equals("REVISION_CONFLICT", stale.error.code)
    assert.equals("# Conflict\n\nExternal edit wins.\n", read(vault .. "/Conflict.md"))

    -- D: plugin confirms the CLI move plan, CLI rewrites links, buffer follows target.
    reset_buffers()
    vim.cmd("edit " .. vim.fn.fnameescape(vault .. "/Move/Source.md"))
    local move_source_buf = vim.api.nvim_get_current_buf()
    local move_done = false
    local move_result
    local move_err
    vim.ui.select = function(_, _, callback)
      callback("Apply")
    end
    assert.is_true(require("miniobsidian.move").move_current("Archive/Source.md", {
      on_complete = function(value, failure)
        move_result = value
        move_err = failure
        move_done = true
      end,
    }))
    assert.is_true(vim.wait(8000, function()
      return move_done
    end, 10))
    assert.is_nil(move_err)
    assert.equals("Archive/Source.md", move_result.target)
    assert.equals(0, vim.fn.filereadable(vault .. "/Move/Source.md"))
    assert.equals(1, vim.fn.filereadable(vault .. "/Archive/Source.md"))
    assert.matches("%[%[Archive/Source%]%]", read(vault .. "/Refs.md"))
    assert.not_matches("%[%[Move/Source%]%]", read(vault .. "/Refs.md"))
    assert.equals(vault .. "/Archive/Source.md", vim.api.nvim_buf_get_name(move_source_buf))
    local backlinks = cli({
      "link",
      "backlinks",
      "Archive/Source.md",
      "--vault",
      vault,
      "--output",
      "json",
    })
    assert.equals(1, #backlinks.data.backlinks.results)

    -- E: an Obsidian-compatible daily file resolves to the same path in plugin and CLI.
    reset_buffers()
    local daily_timestamp = os.time({ year = 2042, month = 3, day = 14, hour = 12 })
    require("miniobsidian.daily").open_today({ timestamp = daily_timestamp })
    assert.is_true(vim.wait(3000, function()
      return vim.api.nvim_buf_get_name(0) == vault .. "/Dailies/2042-03-14.md"
    end, 10))
    local daily = cli({
      "daily",
      "get",
      "--date",
      "2042-03-14",
      "--vault",
      vault,
      "--output",
      "json",
    })
    assert.is_true(daily.data.exists)
    assert.equals("Dailies/2042-03-14.md", daily.data.target.path)
    assert.equals("Dailies/2042-03-14.md", daily.data.note.path)
    assert.equals("2042-03-14", daily.data.note.frontmatter.title)
    assert.equals("daily", daily.data.note.frontmatter.tags[1])

    -- F: dirty Neovim memory + Agent disk update opens a three-way view and blocks writes.
    reset_buffers()
    vim.cmd("edit " .. vim.fn.fnameescape(vault .. "/Status.md"))
    local status_buf = vim.api.nvim_get_current_buf()
    local status = snapshot("Status.md")
    vim.api.nvim_buf_set_lines(status_buf, 2, 3, false, { "Local dirty edit" })
    local status_patch = cli({
      "note",
      "patch",
      "Status.md",
      "--match-file",
      input_file("Before"),
      "--content-file",
      input_file("Agent disk edit"),
      "--if-match",
      status.revision,
      "--vault",
      vault,
      "--output",
      "json",
    })
    vim.ui.select = function(_, _, callback)
      callback(require("miniobsidian.agent_result").actions.keep)
    end
    local inspected, inspect_err = require("miniobsidian.agent_result").inspect_change({
      path = "Status.md",
      revision_before = status.revision,
      revision_after = status_patch.data.note.revision_after,
      summary = "Agent updated disk while Neovim had local edits",
      before_content = status.content,
    })
    assert.is_nil(inspect_err)
    assert.equals("three_way", inspected.kind)
    assert.matches("Before", table.concat(vim.api.nvim_buf_get_lines(inspected.view.base_buf, 0, -1, false), "\n"))
    assert.matches(
      "Agent disk edit",
      table.concat(vim.api.nvim_buf_get_lines(inspected.view.disk_buf, 0, -1, false), "\n")
    )
    assert.matches(
      "Local dirty edit",
      table.concat(vim.api.nvim_buf_get_lines(inspected.view.local_buf, 0, -1, false), "\n")
    )
    assert.equals("Local dirty edit", vim.api.nvim_buf_get_lines(status_buf, 2, 3, false)[1])
    assert.is_true(vim.api.nvim_get_option_value("modified", { buf = status_buf }))
    assert.is_false(require("miniobsidian.external_changes").before_write(status_buf))

    write(summary_path, vim.json.encode({
      schema_version = "three-client-e2e/v1",
      scenarios = {
        {
          id = "A",
          status = "passed",
          invariants = { "frontmatter_preserved", "agent_patch_visible_in_neovim" },
        },
        {
          id = "B",
          status = "passed",
          invariants = { "neovim_note_visible_to_agent", "revision_guarded_status_update" },
        },
        {
          id = "C",
          status = "passed",
          invariants = { "dry_run_precedes_apply", "stale_apply_rejected_without_overwrite" },
        },
        {
          id = "D",
          status = "passed",
          invariants = { "move_plan_confirmed", "links_rewritten", "buffer_tracks_target" },
        },
        {
          id = "E",
          status = "passed",
          invariants = { "shared_daily_path", "frontmatter_consistent" },
        },
        {
          id = "F",
          status = "passed",
          invariants = { "three_way_view_created", "dirty_buffer_preserved", "stale_write_blocked" },
        },
      },
    }) .. "\n")
  end)
end)
