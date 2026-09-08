local helpers = require("tests.helpers")

describe("note move", function()
  local vault
  local original_snacks_input
  local original_lsp_get_clients
  local original_lsp_get_active_clients

  before_each(function()
    vault = helpers.temp_vault()
    helpers.configure(vault)
    original_snacks_input = package.loaded["snacks.input"]
    original_lsp_get_clients = vim.lsp.get_clients
    original_lsp_get_active_clients = vim.lsp.get_active_clients
    package.loaded["snacks.input"] = nil
    package.loaded.snacks = nil
    package.loaded["neo-tree.sources.manager"] = nil
  end)

  after_each(function()
    package.loaded["snacks.input"] = original_snacks_input
    vim.lsp.get_clients = original_lsp_get_clients
    vim.lsp.get_active_clients = original_lsp_get_active_clients
    package.loaded.snacks = nil
    package.loaded["neo-tree.sources.manager"] = nil
    helpers.cleanup(vault)
  end)

  it("moves the current note and updates resolved wikilinks", function()
    local source = vault .. "/Notes/Source.md"
    local reference = vault .. "/Notes/Reference.md"
    vim.fn.writefile({ "# Source", "self [[Source#Part|Here]]" }, source)
    vim.fn.writefile({
      "[[Source]] [[Notes/Source#^block|Alias]] ![[Source]]",
      "`[[Source]]` %% [[Source]] %%",
      "```markdown",
      "[[Source]]",
      "```",
    }, reference)
    require("miniobsidian").invalidate_cache()
    vim.cmd("edit " .. vim.fn.fnameescape(source))

    local result = assert(require("miniobsidian.note").move("Archive/", { notify = false }))

    assert.equals(0, vim.fn.filereadable(source))
    assert.equals(1, vim.fn.filereadable(vault .. "/Archive/Source.md"))
    assert.equals(vim.uv.fs_realpath(vault .. "/Archive/Source.md"), vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)))
    assert.same({ "# Source", "self [[Source#Part|Here]]" }, vim.fn.readfile(vault .. "/Archive/Source.md"))
    assert.same({
      "[[Source]] [[Archive/Source#^block|Alias]] ![[Source]]",
      "`[[Source]]` %% [[Source]] %%",
      "```markdown",
      "[[Source]]",
      "```",
    }, vim.fn.readfile(reference))
    assert.equals(1, result.updated_files)
    assert.equals(1, result.updated_links)
  end)

  it("uses pre-move resolution and leaves ambiguous basename links unchanged", function()
    vim.fn.mkdir(vault .. "/Areas", "p")
    vim.fn.mkdir(vault .. "/Projects", "p")
    local source = vault .. "/Areas/Index.md"
    local reference = vault .. "/Notes/Reference.md"
    vim.fn.writefile({ "# Area" }, source)
    vim.fn.writefile({ "# Project" }, vault .. "/Projects/Index.md")
    vim.fn.writefile({ "ambiguous [[Index]]", "exact [[Areas/Index|Area]]" }, reference)
    require("miniobsidian").invalidate_cache()

    assert(require("miniobsidian.note").move("Archive/", { source = source, notify = false }))

    assert.same({ "ambiguous [[Index]]", "exact [[Archive/Index|Area]]" }, vim.fn.readfile(reference))
  end)

  it("supports an explicit destination note path", function()
    local source = vault .. "/Notes/Old.md"
    local reference = vault .. "/Notes/Reference.md"
    vim.fn.writefile({ "old" }, source)
    vim.fn.writefile({ "[[Old]]" }, reference)
    require("miniobsidian").invalidate_cache()

    local result = assert(require("miniobsidian.note").move("Archive/New", {
      source = source,
      notify = false,
    }))

    assert.equals(vim.uv.fs_realpath(vault .. "/Archive/New.md"), vim.uv.fs_realpath(result.new_path))
    assert.same({ "[[New]]" }, vim.fn.readfile(reference))
  end)

  it("completes safe Vault-relative move directories", function()
    vim.fn.mkdir(vault .. "/Projects/Alpha", "p")
    vim.fn.mkdir(vault .. "/Archive", "p")
    vim.fn.mkdir(vault .. "/.hidden/Secret", "p")

    local move = require("miniobsidian.note_move")
    assert.same({ "Projects/", "Projects/Alpha/" }, move.complete_directories("Pro"))
    assert.same({ "Projects/Alpha/" }, move.complete_directories("", "ObsidianMove Projects/A", 24))
    assert.same(
      { "Projects/", "Projects/Alpha/" },
      vim.fn.getcompletion("Pro", "customlist,v:lua.require'miniobsidian.note_move'.complete_directories")
    )
    assert.is_false(vim.tbl_contains(move.complete_directories(""), ".hidden/"))
  end)

  it("passes only native options to the fallback interactive move prompt", function()
    local source = vault .. "/Notes/Source.md"
    vim.fn.writefile({ "source" }, source)
    vim.cmd("edit " .. vim.fn.fnameescape(source))
    local original_input = vim.ui.input
    local captured
    vim.ui.input = function(opts, callback)
      captured = opts
      callback(nil)
    end

    require("miniobsidian.note").move(nil, { notify = false })
    vim.ui.input = original_input

    assert.equals("customlist,v:lua.require'miniobsidian.note_move'.complete_directories", captured.completion)
    assert.is_nil(captured.win)
  end)

  it("uses Snacks input for completion-menu navigation when available", function()
    local source = vault .. "/Notes/Source.md"
    vim.fn.writefile({ "source" }, source)
    vim.cmd("edit " .. vim.fn.fnameescape(source))
    local captured
    package.loaded.snacks = {}
    package.loaded["snacks.input"] = {
      input = function(opts, callback)
        captured = opts
        callback(nil)
      end,
    }

    require("miniobsidian.note").move(nil, { notify = false })

    assert.equals("customlist,v:lua.require'miniobsidian.note_move'.complete_directories", captured.completion)
    assert.equals("<up>", captured.win.keys.i_up[1])
    assert.equals("<down>", captured.win.keys.i_down[1])
    assert.equals("h", captured.win.keys.i_h[1])
    assert.equals("j", captured.win.keys.i_j[1])
    assert.equals("k", captured.win.keys.i_k[1])
  end)

  it("moves back after an unloaded source and clears a stale target buffer", function()
    local source = vault .. "/Notes/Roundtrip.md"
    local moved = vault .. "/Archive/Roundtrip.md"
    vim.fn.writefile({ "roundtrip" }, source)
    require("miniobsidian").invalidate_cache()
    vim.cmd("edit " .. vim.fn.fnameescape(source))
    local note_buffer = vim.api.nvim_get_current_buf()
    vim.cmd("enew!")
    vim.cmd("bunload " .. note_buffer)
    assert.is_false(vim.api.nvim_buf_is_loaded(note_buffer))

    assert(require("miniobsidian.note").move("Archive/Roundtrip", {
      source = source,
      notify = false,
    }))
    assert.equals(note_buffer, vim.fn.bufnr(moved))

    local stale_target = vim.fn.bufadd(source)
    vim.fn.bufload(stale_target)
    assert.is_true(vim.api.nvim_buf_is_loaded(stale_target))
    assert.same({}, vim.fn.win_findbuf(stale_target))
    assert(require("miniobsidian.note").move("Notes/Roundtrip", {
      source = moved,
      notify = false,
    }))

    assert.equals(1, vim.fn.filereadable(source))
    assert.equals(0, vim.fn.filereadable(moved))
    assert.is_false(vim.api.nvim_buf_is_valid(stale_target))
    assert.equals(note_buffer, vim.fn.bufnr(source))
  end)

  it("renames the current note in place and updates resolved wikilinks", function()
    local source = vault .. "/Notes/Old Name.md"
    local reference = vault .. "/Notes/Reference.md"
    vim.fn.writefile({ "self [[Old Name#Part|Self]]" }, source)
    vim.fn.writefile({ "[[Old Name]]", "![[Notes/Old Name#^block|Shown]]" }, reference)
    require("miniobsidian").invalidate_cache()
    vim.cmd("edit " .. vim.fn.fnameescape(source))
    local observed
    local autocmd = vim.api.nvim_create_autocmd("User", {
      pattern = "MiniObsidianNoteRenamed",
      once = true,
      callback = function(event)
        observed = event.data
      end,
    })

    local result = assert(require("miniobsidian.note").rename("New Name", { notify = false }))

    assert.equals(0, vim.fn.filereadable(source))
    assert.equals(1, vim.fn.filereadable(vault .. "/Notes/New Name.md"))
    assert.equals(vim.uv.fs_realpath(vault .. "/Notes/New Name.md"), vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)))
    assert.same({ "self [[New Name#Part|Self]]" }, vim.fn.readfile(vault .. "/Notes/New Name.md"))
    assert.same({ "[[New Name]]", "![[Notes/New Name#^block|Shown]]" }, vim.fn.readfile(reference))
    assert.equals("rename", result.operation)
    assert.equals(result.new_path, observed.new_path)
    pcall(vim.api.nvim_del_autocmd, autocmd)
  end)

  it("synchronizes matching frontmatter title and first H1 on rename", function()
    local source = vault .. "/Notes/note02.md"
    local reference = vault .. "/Notes/note01.md"
    vim.fn.writefile({
      "---",
      'title: "note02"',
      "date: 2026-08-09",
      "tags: []",
      "---",
      "",
      "# note02",
    }, source)
    vim.fn.writefile({ "# note01", "[[note02]]" }, reference)
    require("miniobsidian").invalidate_cache()

    local result = assert(require("miniobsidian.note").rename("note02.1", {
      source = source,
      notify = false,
    }))

    assert.same({
      "---",
      'title: "note02.1"',
      "date: 2026-08-09",
      "tags: []",
      "---",
      "",
      "# note02.1",
    }, vim.fn.readfile(vault .. "/Notes/note02.1.md"))
    assert.same({ "# note01", "[[note02.1]]" }, vim.fn.readfile(reference))
    assert.equals(2, result.updated_identity_fields)
  end)

  it("notifies interested LSP clients after a note rename", function()
    local source = vault .. "/Notes/note02.md"
    local target = vault .. "/Notes/note03.md"
    vim.fn.writefile({ "# note02" }, source)
    require("miniobsidian").invalidate_cache()
    local notifications = {}
    vim.lsp.get_clients = function()
      return {
        {
          supports_method = function(_, method)
            return method == "workspace/didRenameFiles" or method == "workspace/didChangeWatchedFiles"
          end,
          notify = function(_, method, params)
            notifications[#notifications + 1] = { method = method, params = params }
          end,
        },
      }
    end

    assert(require("miniobsidian.note").rename("note03", {
      source = source,
      notify = false,
    }))

    assert.equals("workspace/didRenameFiles", notifications[1].method)
    local observed_params = notifications[1].params
    local notified_source = vim.uri_to_fname(observed_params.files[1].oldUri)
    assert.equals(vim.fn.fnamemodify(source, ":t"), vim.fn.fnamemodify(notified_source, ":t"))
    assert.equals(
      vim.uv.fs_realpath(vim.fn.fnamemodify(source, ":h")),
      vim.uv.fs_realpath(vim.fn.fnamemodify(notified_source, ":h"))
    )
    assert.equals(vim.uv.fs_realpath(target), vim.uv.fs_realpath(vim.uri_to_fname(observed_params.files[1].newUri)))
    assert.equals("workspace/didChangeWatchedFiles", notifications[2].method)
    assert.equals(3, notifications[2].params.changes[1].type)
    assert.equals(1, notifications[2].params.changes[2].type)
  end)

  it("preserves custom frontmatter and heading titles on rename", function()
    local source = vault .. "/Notes/note02.md"
    vim.fn.writefile({
      "---",
      "title: A custom title",
      "---",
      "# Another heading",
      "# note02",
    }, source)
    require("miniobsidian").invalidate_cache()

    local result = assert(require("miniobsidian.note").rename("note02.1", {
      source = source,
      notify = false,
    }))

    assert.same({
      "---",
      "title: A custom title",
      "---",
      "# Another heading",
      "# note02",
    }, vim.fn.readfile(vault .. "/Notes/note02.1.md"))
    assert.equals(0, result.updated_identity_fields)
  end)

  it("qualifies a short link when the renamed target basename is ambiguous", function()
    local source = vault .. "/Notes/Old.md"
    local reference = vault .. "/Notes/Reference.md"
    vim.fn.mkdir(vault .. "/Projects", "p")
    vim.fn.writefile({ "old" }, source)
    vim.fn.writefile({ "other" }, vault .. "/Projects/New.md")
    vim.fn.writefile({ "[[Old]]", "[[Old.md|Shown]]" }, reference)
    require("miniobsidian").invalidate_cache()

    local result = assert(require("miniobsidian.note").rename("New", {
      source = source,
      notify = false,
    }))

    assert.same({ "[[Notes/New]]", "[[Notes/New.md|Shown]]" }, vim.fn.readfile(reference))
    assert.equals(2, result.updated_links)
  end)

  it("rejects rename paths and existing note names", function()
    local source = vault .. "/Notes/Source.md"
    vim.fn.writefile({ "source" }, source)
    vim.fn.writefile({ "occupied" }, vault .. "/Notes/Occupied.md")
    require("miniobsidian").invalidate_cache()

    local _, path_err = require("miniobsidian.note").rename("Archive/New", {
      source = source,
      notify = false,
    })
    assert.truthy(path_err:find("RENAME_ONLY_FILENAME", 1, true))
    local _, exists_err = require("miniobsidian.note").rename("Occupied", {
      source = source,
      notify = false,
    })
    assert.truthy(exists_err:find("TARGET_EXISTS", 1, true))
    assert.equals(1, vim.fn.filereadable(source))
  end)

  it("renames the note selected in neo-tree", function()
    local source = vault .. "/Notes/Selected.md"
    local reference = vault .. "/Notes/Reference.md"
    vim.fn.writefile({ "selected" }, source)
    vim.fn.writefile({ "[[Selected]]" }, reference)
    require("miniobsidian").invalidate_cache()
    vim.cmd("enew!")
    vim.bo.filetype = "neo-tree"
    package.loaded["neo-tree.sources.manager"] = {
      get_state = function()
        return {
          tree = {
            get_node = function()
              return { type = "file", path = source }
            end,
          },
        }
      end,
    }

    assert(require("miniobsidian.note").rename("Renamed", { notify = false }))

    assert.equals(0, vim.fn.filereadable(source))
    assert.equals(1, vim.fn.filereadable(vault .. "/Notes/Renamed.md"))
    assert.same({ "[[Renamed]]" }, vim.fn.readfile(reference))
  end)

  it("moves the note selected in snacks explorer", function()
    local source = vault .. "/Notes/Selected.md"
    local reference = vault .. "/Notes/Reference.md"
    vim.fn.writefile({ "selected" }, source)
    vim.fn.writefile({ "[[Selected]]" }, reference)
    require("miniobsidian").invalidate_cache()
    vim.cmd("enew!")
    local win = vim.api.nvim_get_current_win()
    package.loaded.snacks = {
      picker = {
        get = function()
          return {
            {
              list = { win = { win = win } },
              selected = function()
                return { { file = source } }
              end,
            },
          }
        end,
      },
    }

    assert(require("miniobsidian.note").move("Archive/Selected", { notify = false }))

    assert.equals(0, vim.fn.filereadable(source))
    assert.equals(1, vim.fn.filereadable(vault .. "/Archive/Selected.md"))
    assert.same({ "[[Selected]]" }, vim.fn.readfile(reference))
  end)

  it("rejects a directory selected in a file tree", function()
    vim.cmd("enew!")
    vim.bo.filetype = "neo-tree"
    package.loaded["neo-tree.sources.manager"] = {
      get_state = function()
        return {
          tree = {
            get_node = function()
              return { type = "directory", path = vault .. "/Notes" }
            end,
          },
        }
      end,
    }

    local result, err = require("miniobsidian.note").rename("Nope", { notify = false })

    assert.is_nil(result)
    assert.truthy(err:find("NOT_A_NOTE_FILE", 1, true))
  end)

  it("rejects unsafe destinations, existing targets, and modified peer buffers", function()
    local source = vault .. "/Notes/Source.md"
    vim.fn.writefile({ "source" }, source)
    vim.fn.mkdir(vault .. "/Archive", "p")
    vim.fn.writefile({ "occupied" }, vault .. "/Archive/Source.md")
    require("miniobsidian").invalidate_cache()

    local _, unsafe_err = require("miniobsidian.note").move("../Outside", { source = source, notify = false })
    assert.truthy(unsafe_err:find("PATH_OUTSIDE_VAULT", 1, true))
    local _, exists_err = require("miniobsidian.note").move("Archive", { source = source, notify = false })
    assert.truthy(exists_err:find("TARGET_EXISTS", 1, true))

    local peer = vault .. "/Notes/Peer.md"
    vim.fn.writefile({ "peer" }, peer)
    vim.cmd("edit " .. vim.fn.fnameescape(peer))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
    local _, modified_err = require("miniobsidian.note").move("Elsewhere/", {
      source = source,
      notify = false,
    })
    assert.truthy(modified_err:find("UNSAVED_PEERS", 1, true))
    assert.equals(1, vim.fn.filereadable(source))
  end)

  it("rolls the move back when a reference write fails", function()
    local source = vault .. "/Notes/Source.md"
    local reference = vault .. "/Notes/Reference.md"
    vim.fn.writefile({ "source" }, source)
    vim.fn.writefile({ "[[Notes/Source]]" }, reference)
    require("miniobsidian").invalidate_cache()

    local fs = require("miniobsidian.fs")
    local original_write = fs.write_atomic
    local failed = false
    fs.write_atomic = function(path, content)
      if not failed then
        failed = true
        return nil, "injected failure"
      end
      return original_write(path, content)
    end
    local result, err = require("miniobsidian.note").move("Archive/", { source = source, notify = false })
    fs.write_atomic = original_write

    assert.is_nil(result)
    assert.truthy(err:find("UPDATE_REFERENCES_FAILED", 1, true))
    assert.equals(1, vim.fn.filereadable(source))
    assert.equals(0, vim.fn.filereadable(vault .. "/Archive/Source.md"))
    assert.same({ "[[Notes/Source]]" }, vim.fn.readfile(reference))
  end)

  it("escapes synchronized YAML titles for quoted and plain scalars", function()
    for index, title in ipairs({ 'title: "Old"', "title: 'Old'", "title: Old" }) do
      local source = vault .. "/Notes/Old.md"
      vim.fn.writefile({ "---", title, "---", "# Old" }, source)
      local result = assert(require("miniobsidian.note").rename([[A "quote" and 'single']], {
        source = source,
        notify = false,
      }))
      local output = vim.fn.readfile(result.new_path)
      local expected = index == 2 and [[title: 'A "quote" and ''single''']] or [[title: "A \"quote\" and 'single'"]]
      assert.equals(expected, output[2])
      assert.equals([[# A "quote" and 'single']], output[4])
      vim.fn.delete(result.new_path)
    end
  end)

  it("preserves fenced examples and updates only the first real heading", function()
    local source = vault .. "/Notes/Old.md"
    local reference = vault .. "/Notes/Ref.md"
    local example = { "````md", "```", "# Old", "[[Old]]", "````", "<!-- # Old -->", "%%", "# Old", "%%" }
    local content = vim.list_extend(vim.deepcopy(example), { "# Old", "# Old" })
    vim.fn.writefile(content, source)
    vim.fn.writefile(vim.list_extend(vim.deepcopy(example), { "[[Old]]" }), reference)
    local result = assert(require("miniobsidian.note").rename("New", { source = source, notify = false }))
    assert.same(vim.list_extend(vim.deepcopy(example), { "# New", "# Old" }), vim.fn.readfile(result.new_path))
    assert.same(vim.list_extend(vim.deepcopy(example), { "[[New]]" }), vim.fn.readfile(reference))
    assert.equals(1, result.updated_identity_fields)
    assert.equals(1, result.updated_links)
  end)

  it("preserves links to other notes when the new basename introduces ambiguity", function()
    local source = vault .. "/Notes/Old.md"
    local reference = vault .. "/Notes/Ref.md"
    vim.fn.mkdir(vault .. "/Dir", "p")
    vim.fn.writefile({ "old" }, source)
    vim.fn.writefile({ "new" }, vault .. "/Dir/New.md")
    vim.fn.writefile({ "[[New]] ![[New.md#Part|Alias]] [[Dir/New]] [[Old]]" }, reference)
    local result = assert(require("miniobsidian.note").rename("New", { source = source, notify = false }))
    assert.same({ "[[Dir/New]] ![[Dir/New.md#Part|Alias]] [[Dir/New]] [[Notes/New]]" }, vim.fn.readfile(reference))
    assert.equals(3, result.updated_links)
    local resolved = assert(
      require("miniobsidian.wikilink").resolve(
        { target = "Dir/New" },
        require("miniobsidian").get_all_notes(true),
        vault
      )
    )
    assert.equals("Dir/New", resolved.id)
  end)

  it("keeps pasted attachments reachable after a cross-directory move", function()
    local source = vault .. "/Notes/Old.md"
    vim.fn.mkdir(vault .. "/Assets", "p")
    vim.fn.writefile({ "image" }, vault .. "/Assets/image.png")
    vim.fn.writefile({ "# Old", "![](../Assets/image.png)" }, source)
    vim.cmd("edit " .. vim.fn.fnameescape(source))
    local result = assert(require("miniobsidian.note").move("Archive/Deep/Old", { notify = false }))
    local expected = { "# Old", "![](../../Assets/image.png)" }
    assert.same(expected, vim.fn.readfile(result.new_path))
    assert.same(expected, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    assert.equals(1, result.updated_links)
    assert.equals(1, vim.fn.filereadable(vim.fn.fnamemodify(result.new_path, ":h") .. "/../../Assets/image.png"))
  end)

  it("rolls back already-written attachment paths when a later reference update fails", function()
    local source = vault .. "/Notes/AAA.md"
    local reference = vault .. "/Notes/ZZZ.md"
    vim.fn.mkdir(vault .. "/Assets", "p")
    vim.fn.writefile({ "image" }, vault .. "/Assets/image.png")
    vim.fn.writefile({ "![](../Assets/image.png)" }, source)
    vim.fn.writefile({ "[[Notes/AAA]]" }, reference)
    local fs = require("miniobsidian.fs")
    local original = fs.write_atomic
    local calls = 0
    fs.write_atomic = function(path, content)
      calls = calls + 1
      if calls == 2 then
        return nil, "injected later failure"
      end
      return original(path, content)
    end
    local result, err = require("miniobsidian.note").move("Archive/Deep/AAA", { source = source, notify = false })
    fs.write_atomic = original
    assert.is_nil(result)
    assert.truthy(err:find("UPDATE_REFERENCES_FAILED", 1, true))
    assert.same({ "![](../Assets/image.png)" }, vim.fn.readfile(source))
    assert.same({ "[[Notes/AAA]]" }, vim.fn.readfile(reference))
    assert.equals(0, vim.fn.filereadable(vault .. "/Archive/Deep/AAA.md"))
  end)

  it("synchronizes an escaped YAML title again on a subsequent rename", function()
    local source = vault .. "/Notes/Old.md"
    vim.fn.writefile({ "---", 'title: "Old"', "---", "# Old" }, source)
    local first = assert(require("miniobsidian.note").rename([[A "quote"]], { source = source, notify = false }))
    local second = assert(require("miniobsidian.note").rename("Final", { source = first.new_path, notify = false }))
    assert.same({ "---", 'title: "Final"', "---", "# Final" }, vim.fn.readfile(second.new_path))
  end)

  it("does not skip a custom first heading made entirely of inline code", function()
    local source = vault .. "/Notes/Old.md"
    local content = { "# `Custom`", "# Old" }
    vim.fn.writefile(content, source)
    local result = assert(require("miniobsidian.note").rename("New", { source = source, notify = false }))
    assert.same(content, vim.fn.readfile(result.new_path))
    assert.equals(0, result.updated_identity_fields)
  end)

  it("keeps Markdown self-links pointing at the moved note", function()
    local source = vault .. "/Notes/Old.md"
    vim.fn.writefile({ "[self](Old.md#Part)", "[other](Other.md)" }, source)
    local renamed = assert(require("miniobsidian.note").rename("New", { source = source, notify = false }))
    assert.same({ "[self](New.md#Part)", "[other](Other.md)" }, vim.fn.readfile(renamed.new_path))
    local moved =
      assert(require("miniobsidian.note").move("Archive/Deep/New", { source = renamed.new_path, notify = false }))
    assert.same({ "[self](New.md#Part)", "[other](../../Notes/Other.md)" }, vim.fn.readfile(moved.new_path))
  end)
end)
