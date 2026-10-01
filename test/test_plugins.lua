-- Plugin smoke tests
-- Load-only tests for UI plugins, behavioral tests where APIs are stable
local h = dofile "test/helpers.lua"
local trigger = require("lz.n").trigger_load

--
-- Behavioral tests (tests one key function that works headlessly)
--

h.test("telescope: can open picker", function()
  trigger "telescope.nvim"
  require("telescope.builtin").help_tags()
  vim.wait(2000, function() return vim.bo.filetype == "TelescopePrompt" end, 20)
  h.eq("TelescopePrompt", vim.bo.filetype, "the help_tags prompt never opened")
  require("telescope.actions").close(vim.api.nvim_get_current_buf())
  h.leave_picker()
  h.eq("n", vim.fn.mode(1), "left insert mode behind")
end)

-- telescope master dropped its Nvim 0.10 compat shims, including the wrappers that
-- used to stand in for vim.validate/vim.str_byteindex/vim.hl.range. transform_path
-- runs straight through the un-shimmed path, so it catches that fallout.
h.test("telescope: our setup options survived", function()
  trigger "telescope.nvim"
  local conf = require("telescope.config").values

  local pd = conf.path_display
  h.assert(type(pd) == "table" and pd.shorten, "path_display.shorten lost: " .. vim.inspect(pd))
  h.eq(
    "/one/two/thr/fou/five.lua",
    require("telescope.utils").transform_path({ path_display = pd }, "/one/two/three/four/five.lua"),
    "path_display shorten no longer applied"
  )

  h.assert(conf.mappings and conf.mappings.i and conf.mappings.i["<C-j>"], "our insert-mode <C-j> mapping was dropped")
  h.assert(require("telescope").extensions["zf-native"], "zf-native extension not registered")
end)

-- ripgrep's --hidden is baked into the finder's command when the picker is built, so
-- the toggle relaunches the picker. Nothing upstream provides the action, so check both
-- that it is registered and that it reaches a live prompt.
h.test("telescope: live_grep has a hidden-file toggle", function()
  trigger "telescope.nvim"
  local mappings = (require("telescope.config").pickers.live_grep or {}).mappings
  h.assert(mappings, "live_grep has no picker mappings")
  h.eq("function", type(mappings.i["<M-h>"]), "no insert mode hidden toggle")
  h.eq("function", type(mappings.n["<M-h>"]), "no normal mode hidden toggle")

  if vim.fn.executable "rg" ~= 1 then
    print "    (no rg; skipped driving the picker)"
    return
  end

  require("telescope.builtin").live_grep()
  vim.wait(2000, function() return vim.bo.filetype == "TelescopePrompt" end, 20)
  local prompt = vim.api.nvim_get_current_buf()
  local opened = vim.bo[prompt].filetype
  local bound = false
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(prompt, "i")) do
    if map.lhs == "<M-h>" then bound = true end
  end

  -- closing wipes the prompt buffer, so everything above had to be read first
  require("telescope.actions").close(prompt)
  h.leave_picker()
  h.eq("TelescopePrompt", opened, "live_grep prompt never opened")
  h.assert(bound, "<M-h> not bound in the live_grep prompt")
end)

-- grep_string must NOT get the toggle: a picker does not keep the opts it was built
-- from, so relaunching it would drop `search` and silently re-grep
-- vim.fn.expand "<cword>" of whatever buffer actions.close returned to, while the
-- caller's prompt_title went on claiming the original term.
h.test("telescope: grep_string keeps its search term, and no toggle can take it away", function()
  trigger "telescope.nvim"
  h.eq(nil, (require("telescope.config").pickers.grep_string or {}).mappings, "grep_string got picker mappings again")

  if vim.fn.executable "rg" ~= 1 then
    print "    (no rg; skipped driving the picker)"
    return
  end

  -- a term this repo has few of, so a fallback to <cword> could not look the same
  require("telescope.builtin").grep_string { search = "npinsToPluginsAttrs" }
  vim.wait(5000, function() return vim.bo.filetype == "TelescopePrompt" end, 20)
  local prompt = vim.api.nvim_get_current_buf()
  local picker = require("telescope.actions.state").get_current_picker(prompt)
  vim.wait(5000, function() return picker.manager and picker.manager:num_results() > 0 end, 20)

  local title = picker.prompt_title
  local results = picker.manager and picker.manager:num_results() or 0
  local bound = false
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(prompt, "i")) do
    if map.lhs == "<M-h>" then bound = true end
  end

  require("telescope.actions").close(prompt)
  h.leave_picker()
  h.assert(not bound, "<M-h> is bound in the grep_string prompt, so it can be corrupted")
  h.eq("Find Word (npinsToPluginsAttrs)", title, "the title stopped naming the search term")
  h.assert(results > 0 and results < 20, "grep_string searched something else: " .. results .. " results")
end)

h.test("trouble: diagnostics command works", function()
  trigger "trouble.nvim"
  local trouble = require "trouble"
  -- Verify API exists and is callable
  h.assert(type(trouble.toggle) == "function", "trouble.toggle missing")
  h.assert(type(trouble.open) == "function", "trouble.open missing")
end)

-- trouble's lsp source is what broke on Nvim 0.12: it used to call the removed
-- vim.lsp.util._str_byteindex_enc and client.request in the dot form. Requiring the
-- module and driving a real view is what actually exercises that code.
h.test("trouble: lsp source loads and a view opens and closes", function()
  trigger "trouble.nvim"
  h.require_ok "trouble.sources.lsp"

  local trouble = require "trouble"
  trouble.open { mode = "diagnostics" }
  vim.wait(200, function() return false end)
  trouble.close()
  vim.wait(100, function() return false end)

  vim.cmd "Trouble qflist toggle"
  vim.wait(200, function() return false end)
  vim.cmd "Trouble qflist close"
end)

h.test("gitsigns: API available", function()
  trigger "gitsigns.nvim"
  local gitsigns = require "gitsigns"
  h.assert(type(gitsigns.stage_hunk) == "function", "gitsigns.stage_hunk missing")
  h.assert(type(gitsigns.blame_line) == "function", "gitsigns.blame_line missing")
end)

-- gitsigns 2.0 deprecated undo_stage_hunk (stage_hunk toggles staged hunks now) and
-- toggle_deleted (preview_hunk_inline supersedes it). Our mappings live in on_attach,
-- which only runs for buffers in a real repo, so drive it directly.
h.test("gitsigns: our mappings call the non-deprecated actions", function()
  trigger "gitsigns.nvim"

  -- gitsigns aborts setup outright when git is missing, so our config is never
  -- recorded: `nix flake check` builds from the store, which has no git on PATH.
  if vim.fn.executable "git" ~= 1 then
    print "    (no git; gitsigns skips setup, skipped)"
    return
  end

  local gitsigns = require "gitsigns"
  local on_attach = require("gitsigns.config").config.on_attach
  h.assert(type(on_attach) == "function", "our on_attach was not recorded")

  vim.cmd "enew"
  local buf = vim.api.nvim_get_current_buf()
  local ok, err = pcall(function()
    on_attach(buf)
    local function callback(lhs) return vim.fn.maparg(lhs, "n", false, true).callback end
    -- there is no per-hunk unstage left: stage_hunk toggles, so <leader>hs already
    -- covers it, and <leader>hU must not be a second copy of the same action
    h.eq(gitsigns.reset_buffer_index, callback "<leader>hU", "<leader>hU should reset_buffer_index")
    h.eq(gitsigns.stage_hunk, callback "<leader>hs", "<leader>hs should stage_hunk")
    h.assert(callback "<leader>hU" ~= callback "<leader>hs", "<leader>hU duplicates <leader>hs again")
    -- preview_hunk_inline clears itself on CursorMoved, so it lives in the git
    -- namespace rather than pretending to be a <leader>t toggle
    h.eq(gitsigns.preview_hunk_inline, callback "<leader>hi", "<leader>hi should preview_hunk_inline")
    h.eq(nil, callback "<leader>td", "<leader>td is back in the toggle namespace")
    h.eq(gitsigns.toggle_current_line_blame, callback "<leader>tb", "<leader>tb should be the real toggle")
    h.eq(gitsigns.show_commit, callback "<leader>hc", "<leader>hc should show_commit")

    -- and nothing we bind may be one of the actions gitsigns has since deprecated
    local retired = { "undo_stage_hunk", "toggle_deleted", "next_hunk", "prev_hunk" }
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      for _, name in ipairs(retired) do
        h.assert(map.callback ~= gitsigns[name], map.lhs .. " is bound to the deprecated " .. name)
      end
    end
  end)

  vim.cmd "bwipeout!"
  if not ok then error(err) end
end)

-- <leader>hU runs the only real unstage gitsigns still has. That one only rewrites
-- the index, which is what separates it from <leader>hR, so drive it against a
-- throwaway repo and check both.
h.test("gitsigns: <leader>hU unstages the index and leaves the worktree alone", function()
  trigger "gitsigns.nvim"

  if vim.fn.executable "git" ~= 1 then
    print "    (no git; gitsigns skips setup, skipped)"
    return
  end

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local function git(...) return vim.system({ "git", "-C", dir, ... }, { text = true }):wait().stdout or "" end
  local function staged() return git("diff", "--cached", "--name-only") end
  local function until_true(fn)
    for _ = 1, 100 do
      if fn() then return true end
      vim.wait(50)
    end
    return false
  end

  git("init", "-q", "-b", "main")
  git("config", "user.email", "wim@example.com")
  git("config", "user.name", "wim")
  local file = dir .. "/hunk.txt"
  vim.fn.writefile({ "one", "two", "three" }, file)
  git("add", "hunk.txt")
  git("commit", "-qm", "init")

  vim.cmd.edit(file)
  local buf = vim.api.nvim_get_current_buf()
  local ok, err = pcall(function()
    vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "TWO" })
    vim.cmd "silent write"
    h.assert(
      until_true(function() return #(require("gitsigns").get_hunks(buf) or {}) > 0 end),
      "gitsigns never saw a hunk"
    )

    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    vim.api.nvim_feedkeys(" hs", "x", false)
    h.assert(until_true(function() return staged():find "hunk.txt" ~= nil end), "<leader>hs did not stage the hunk")

    vim.api.nvim_feedkeys(" hU", "x", false)
    h.assert(
      until_true(function() return staged():find "hunk.txt" == nil end),
      "<leader>hU did not unstage: " .. staged()
    )
    h.assert(git("diff", "--name-only"):find "hunk.txt", "<leader>hU reset the worktree, not just the index")
    h.eq("TWO", vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1], "<leader>hU changed the buffer")
  end)

  vim.cmd "bwipeout!"
  vim.fn.delete(dir, "rf")
  if not ok then error(err) end
end)

h.test("treesitter-context: API available", function()
  trigger "nvim-treesitter-context"
  local ctx = require "treesitter-context"
  h.assert(type(ctx.go_to_context) == "function", "go_to_context missing")
end)

h.test("mini.surround: API available", function()
  local surround = require "mini.surround"
  h.assert(type(surround.add) == "function", "surround.add missing")
  h.assert(type(surround.delete) == "function", "surround.delete missing")
end)

h.test("mini.pairs: API available", function()
  local pairs = require "mini.pairs"
  h.assert(type(pairs.open) == "function", "pairs.open missing")
end)

-- neo-tree opens its window off a scheduled callback, so wait for it rather than
-- closing the window that merely happens to be current
h.test("neo-tree: can open", function()
  trigger "neo-tree.nvim"
  vim.cmd "Neotree"
  vim.wait(2000, function() return vim.bo.filetype == "neo-tree" end)
  h.eq("neo-tree", vim.bo.filetype, "neo-tree window did not open")
  vim.cmd "Neotree close"
  vim.wait(1000, function() return vim.bo.filetype ~= "neo-tree" end)
  h.assert(vim.bo.filetype ~= "neo-tree", "neo-tree window did not close")
end)

-- guards against option renames on neo-tree's main branch, which is where 3.x
-- releases are cut from now that v3.x has stopped moving
h.test("neo-tree: our setup options survived", function()
  trigger "neo-tree.nvim"
  local cfg = require("neo-tree").config
  h.assert(cfg, "neo-tree config missing")
  h.eq(true, cfg.close_if_last_window, "close_if_last_window not applied")
  h.eq(true, cfg.filesystem.use_libuv_file_watcher, "use_libuv_file_watcher not applied")
  h.eq(true, cfg.filesystem.group_empty_dirs, "group_empty_dirs not applied")
end)

--
-- Load-only tests (UI plugins, motion plugins, or complex setup required)
--

h.test("mini.indentscope", function() h.require_ok "mini.indentscope" end)
h.test("mini.icons", function() h.require_ok "mini.icons" end)
h.test("blink.cmp: set up with the nix built rust matcher", function()
  h.require_ok "blink.cmp"
  h.eq("super-tab", require("blink.cmp.config").keymap.preset)
  h.eq("rust", require("blink.cmp.fuzzy").implementation_type)
end)
h.test("rose-pine", function() h.require_ok "rose-pine" end)
h.test("plenary", function() h.require_ok "plenary" end)
h.test("nvim-web-devicons", function() h.require_ok "nvim-web-devicons" end)

h.test("leap.nvim: f/t motions jump, case sensitively, without deprecation warnings", function()
  trigger "leap.nvim"
  h.require_ok "leap"

  vim.cmd "tabnew"
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha bravo charlie Delta" })

  local warnings = {}
  local notify = vim.notify
  vim.notify = function(msg, level, opts)
    if level == vim.log.levels.WARN then table.insert(warnings, msg) end
    return notify(msg, level, opts)
  end

  local function feed(keys)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_feedkeys(keys, "x", false)
    return vim.api.nvim_win_get_cursor(0)[2]
  end

  local ok, err = pcall(function()
    h.eq(12, feed "fc", "f should jump to the c of charlie")
    h.eq(17, feed "te", "t should stop before the e of charlie")
    -- lowercase d must not match the capital D of Delta, leaving the cursor put
    h.eq(0, feed "fd", "f should be case sensitive")
    h.eq(0, #warnings, "leap warned: " .. table.concat(warnings, " "))
  end)

  vim.notify = notify
  vim.cmd "tabclose!"
  vim.api.nvim_buf_delete(buf, { force = true })
  if not ok then error(err) end
end)
-- Visitor mode rides upstream's keys, which means gs is no longer cross-window
-- leaping: that moved to gW. The <Plug> keys only exist once leap is packadded, and
-- lz.n's `keys` list has to name every trigger or the real mappings never get set.
h.test("leap.nvim: visitor mode keys, and from-window moved to gW", function()
  trigger "leap.nvim"

  local function rhs(lhs, mode) return vim.fn.maparg(lhs, mode, false, true).rhs end
  h.eq("<Plug>(leap-visit)", rhs("gs", "n"), "gs should be visit now")
  h.eq("<Plug>(leap-visit-linewise)", rhs("gS", "n"))
  h.eq("<Plug>(leap-visit-text-object)", rhs("ar", "o"))
  h.eq("<Plug>(leap-visit-inner-text-object)", rhs("ir", "x"))
  h.eq("<Plug>(leap-visit-line)", rhs("rr", "o"))
  h.eq("<Plug>(leap-from-window)", rhs("gW", "n"))

  -- and each of those has to resolve to something leap's plugin/init.lua defined
  for mode, plugs in pairs {
    n = { "<Plug>(leap-visit)", "<Plug>(leap-visit-linewise)", "<Plug>(leap-from-window)" },
    x = { "<Plug>(leap-visit-text-object)", "<Plug>(leap-visit-inner-text-object)" },
    o = { "<Plug>(leap-visit-line)" },
  } do
    for _, plug in ipairs(plugs) do
      h.assert(not vim.tbl_isempty(vim.fn.maparg(plug, mode, false, true)), plug .. " unmapped in " .. mode)
    end
  end

  -- gw is still vim's own "format and keep the cursor" operator
  h.assert(vim.tbl_isempty(vim.fn.maparg("gw", "n", false, true)), "gw should be left to vim")
end)

-- Visits are asynchronous, which makes them awkward to drive headlessly. leap chains
-- vim.schedule hops, and each hop pushes the next keys into the typeahead, so a single
-- feedkeys with the x flag would run dry long before the jump and the leap input would
-- be eaten as plain normal mode keys. So feed only the keys that reach `visit()`, queue
-- the leap input for leap's own getcharstr, and from then on let every scheduled
-- callback run before executing what it queued: flushing early loses the ModeChanged
-- that tells leap the remote action is done, and the visit never comes back.
local function visit(keys, queued, done)
  vim.api.nvim_feedkeys(vim.keycode(keys), "x", false)
  vim.api.nvim_feedkeys(vim.keycode(queued), "n", false)
  for _ = 1, 20 do
    h.settle(8)
    if done() then return end
    vim.api.nvim_feedkeys("", "x", false)
  end
end

-- A visit followed by a yank should bring the text back: `yar w` grabs a remote word
-- and our VisitDone handler pastes it where the visit started (:h leap-visit-autopaste).
-- Run with 'clipboard' left as configured, which is the whole point: the handler has to
-- paste from '"' by name, because the register the visit reports may be '+' and reading
-- that goes out to a clipboard provider headless nvim has no terminal to answer.
h.test("leap.nvim: a remote yank is pasted back at the origin", function()
  trigger "leap.nvim"

  h.eq("", vim.o.clipboard, "this test is only meaningful with the configured clipboard")
  local register = vim.fn.getreg '"'
  vim.cmd "tabnew"
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "X one two", "alpha bravo charlie" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local ok, err = pcall(function()
    -- br picks out bravo, and s is the first of leap's default labels: a visit never
    -- autojumps, so even a single target has to be confirmed with its label
    visit("yarw", "brs", function() return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= "X one two" end)
    h.eq("Xbravo  one two", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1], "the remote word was not pasted back")
    h.eq("alpha bravo charlie", vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1], "the visited line was changed")
    h.eq("n", vim.fn.mode(1), "the visit did not end in normal mode")
  end)

  vim.cmd "tabclose!"
  vim.api.nvim_buf_delete(buf, { force = true })
  vim.fn.setreg('"', register)
  if not ok then error(err) end
end)

-- The guards, which are what stops the autopaste from clobbering the buffer on every
-- visit: only a yank pastes, only into the default register, and never from an empty
-- one (which would be a bare E353).
h.test("leap.nvim: autopaste leaves everything else alone", function()
  trigger "leap.nvim"

  h.eq("", vim.o.clipboard, "this test is only meaningful with the configured clipboard")
  local register = vim.fn.getreg '"'
  vim.cmd "tabnew"
  local buf = vim.api.nvim_get_current_buf()
  local function reset()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "X one two", "alpha bravo charlie" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  end

  local ok, err = pcall(function()
    -- a remote delete fills the unnamed register just like a yank does, so only the
    -- operator tells them apart
    reset()
    visit("darw", "brs", function() return vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1] ~= "alpha bravo charlie" end)
    h.eq("X one two", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1], "a remote delete pasted")
    h.eq("alpha charlie", vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1], "the remote delete did not happen")

    -- the remaining cases are about the register, and leap's own data is all the
    -- handler reads, so hand it the same shape visit() passes
    local function visit_done(data) vim.api.nvim_exec_autocmds("User", { pattern = "VisitDone", data = data }) end

    reset()
    vim.fn.setreg('"', "")
    visit_done { mode = "v", register = '"' }
    h.eq("X one two", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1], "an empty register still pasted")

    vim.fn.setreg('"', "NOPE")
    visit_done { mode = "v", register = "a" }
    h.eq("X one two", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1], "an explicit register still pasted")

    -- and the paths that should paste still do, so the guards above are not just
    -- switching the whole thing off. '+' is what v:register reports for a visit that
    -- named no register, and is accepted so an explicit "+yarw autopastes too.
    visit_done { mode = "v", register = '"' }
    h.eq("XNOPE one two", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1], "a visual mode visit did not paste")

    reset()
    visit_done { mode = "V", register = "+" }
    h.eq(
      "XNOPE one two",
      vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1],
      "a visit naming the clipboard register did not paste"
    )
  end)

  vim.cmd "tabclose!"
  vim.api.nvim_buf_delete(buf, { force = true })
  vim.fn.setreg('"', register)
  if not ok then error(err) end
end)

h.test("leap.nvim: gW leaps into another window", function()
  trigger "leap.nvim"

  vim.cmd "tabnew"
  local origin = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(origin, 0, -1, false, { "the origin line" })

  vim.cmd "vsplit"
  local target = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, target)
  vim.api.nvim_buf_set_lines(target, 0, -1, false, { "aaa bbb zebra ccc" })
  local target_win = vim.api.nvim_get_current_win()
  vim.cmd "wincmd p"

  local ok, err = pcall(function()
    vim.api.nvim_feedkeys("gWze", "x", false)
    h.eq(target_win, vim.api.nvim_get_current_win(), "gW did not leap into the other window")
    h.eq(8, vim.api.nvim_win_get_cursor(0)[2], "gW did not land on zebra")
  end)

  vim.cmd "tabclose!"
  vim.api.nvim_buf_delete(origin, { force = true })
  vim.api.nvim_buf_delete(target, { force = true })
  if not ok then error(err) end
end)

-- which-key defers the rest of its setup to VimEnter, which never fires headlessly,
-- so only the parts recorded by setup() itself are checkable here
h.test("which-key.nvim", function()
  trigger "which-key.nvim"
  h.require_ok "which-key"
  h.eq("modern", require("which-key.config").options.preset, "our modern preset was not recorded")
  h.assert(type(require("which-key").add) == "function", "which-key.add (v3 spec API) missing")
end)
h.test("toggleterm.nvim", function()
  trigger "toggleterm.nvim"
  h.require_ok "toggleterm"
end)
h.test("neotest", function()
  trigger "neotest"
  h.require_ok "neotest"
end)

-- neotest pulls in nvim-nio, so run a real async task: nio is the piece that would
-- break if its coroutine plumbing regressed
h.test("nvim-nio: async task runs to completion", function()
  trigger "neotest"
  local nio = require "nio"
  local done = false
  nio.run(function()
    nio.sleep(1)
    done = true
  end)
  vim.wait(1000, function() return done end)
  h.assert(done, "nio task did not complete")
end)
h.test("other.nvim", function()
  trigger "other.nvim"
  h.require_ok "other-nvim"
end)
h.test("bufferline.nvim", function()
  trigger "bufferline.nvim"
  h.require_ok "bufferline"
end)
h.test("noice.nvim", function()
  trigger "noice.nvim"
  h.require_ok "noice"
end)
h.test("lualine.nvim", function()
  trigger "lualine.nvim"
  h.require_ok "lualine"
end)
h.test("neorg", function()
  trigger "neorg"
  h.require_ok "neorg"
end)

-- diffview-plus has no spec of its own: the jujutsu.nvim spec packadds it and sources
-- its plugin/diffview.lua by hand. The fork kept the upstream `diffview` module name
-- and every `Diffview*` command, which is what makes the swap off the abandoned
-- sindrets repo a drop-in, so assert all of that rather than just that it loads.
h.test("diffview-plus: loads via the jujutsu.nvim spec, with its commands registered", function()
  trigger "jujutsu.nvim"
  h.require_ok "diffview"
  h.require_ok "diffview.lib"

  local commands = vim.api.nvim_get_commands {}
  for _, cmd in ipairs { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewToggle" } do
    h.assert(commands[cmd], "command :" .. cmd .. " not registered")
  end
end)

-- Needs real history, so it only runs against a working copy: `nix flake check` builds
-- from the flake source in the store, which has no .git and no git on PATH.
h.test("diffview-plus: opens and closes a diff of real history", function()
  trigger "jujutsu.nvim"

  if vim.fn.isdirectory ".git" ~= 1 or vim.fn.executable "git" ~= 1 then
    print "    (no git working copy; skipped driving a diff)"
    return
  end

  -- jujutsu.nvim's "diffview" preset shells out to `DiffviewOpen <sha>^!`, so drive
  -- that exact form against this repo's own history.
  local lib = require "diffview.lib"
  local tabs_before = #vim.api.nvim_list_tabpages()
  local wins_before = #vim.api.nvim_list_wins()
  vim.cmd "DiffviewOpen HEAD^!"

  -- The view opens before its file list is fetched, so wait for the entries.
  vim.wait(20000, function()
    local ok, ready = pcall(function()
      local v = lib.get_current_view()
      return v ~= nil and v.files ~= nil and v.files:len() > 0
    end)
    return ok and ready == true
  end, 50)

  -- Let the view come to rest before closing it. Its entries load through a chain of
  -- coroutines awaiting git jobs, and pulling the windows out from under one of them is
  -- what used to spray "Invalid window id" tracebacks over whichever test ran next.
  vim.wait(1000, function() return false end)
  h.settle(4)

  -- Collect first, assert after closing, so a failure can't leave a tab behind.
  local view = lib.get_current_view()
  local file_count = view and view.files and view.files:len() or 0
  local tabs_after = #vim.api.nvim_list_tabpages()
  local panel_shown = false
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "DiffviewFiles" then panel_shown = true end
  end

  -- get_current_view() goes nil as soon as the tab is gone, well before the view's own
  -- coroutines have unwound. Settling on the window and tabpage counts instead keeps
  -- them from finishing inside the next test and raising "Invalid window id" there.
  vim.cmd "DiffviewClose"
  local function torn_down()
    return lib.get_current_view() == nil
      and #vim.api.nvim_list_tabpages() == tabs_before
      and #vim.api.nvim_list_wins() == wins_before
  end
  vim.wait(10000, torn_down, 50)
  h.settle(4)

  h.assert(view, "no diff view was created")
  h.assert(file_count > 0, "diff view listed no files for HEAD^!")
  h.eq(tabs_before + 1, tabs_after, "diff view did not open in its own tabpage")
  h.assert(panel_shown, "diffview file panel window never appeared")
  h.assert(
    torn_down(),
    string.format(
      "diff view did not tear down: view=%s tabs=%d/%d wins=%d/%d",
      tostring(lib.get_current_view()),
      #vim.api.nvim_list_tabpages(),
      tabs_before,
      #vim.api.nvim_list_wins(),
      wins_before
    )
  )
end)

-- This repo is jj-colocated and diffview tries git before jj, so only <leader>jh
-- asks for the jj adapter, and only for the duration of the command. Drive the key
-- rather than the command, and assert which adapter served the view.
h.test("diffview-plus: <leader>jh file history is served by the jj adapter", function()
  trigger "jujutsu.nvim"

  if vim.fn.isdirectory ".jj" ~= 1 or vim.fn.executable "jj" ~= 1 then
    print "    (no jj working copy; skipped driving the file history)"
    return
  end

  vim.cmd.edit "will/lua/will/options.lua"
  local buf = vim.api.nvim_get_current_buf()

  local lib = require "diffview.lib"
  local tabs_before = #vim.api.nvim_list_tabpages()
  local wins_before = #vim.api.nvim_list_wins()
  vim.api.nvim_feedkeys(" jh", "x", false)

  -- the view opens before its log entries are fetched, so wait for the panel
  vim.wait(15000, function()
    local ok, ready = pcall(function()
      local v = lib.get_current_view()
      return v ~= nil and v.panel ~= nil and v.panel:num_items() > 0
    end)
    return ok and ready == true
  end, 50)

  -- same as above: let the view's coroutines finish before the windows go away
  vim.wait(1000, function() return false end)
  h.settle(4)

  -- collect first, assert after closing, so a failure can't leave a tab behind
  local view = lib.get_current_view()
  local adapter = view and view.adapter and view.adapter.config_key
  local items = view and view.panel and view.panel:num_items() or 0
  local leaked = require("diffview.config").get_config().preferred_adapter

  vim.cmd "DiffviewClose"
  local function torn_down()
    return lib.get_current_view() == nil
      and #vim.api.nvim_list_tabpages() == tabs_before
      and #vim.api.nvim_list_wins() == wins_before
  end
  vim.wait(10000, torn_down, 50)
  h.settle(4)
  vim.api.nvim_buf_delete(buf, { force = true })

  h.assert(torn_down(), "the file history view did not tear down")
  h.assert(view, "no file history view was created")
  h.eq("jj", adapter, "the file history was not served by the jj adapter")
  h.assert(items > 0, "the file history listed no changes")
  -- jujutsu.nvim's own `DiffviewOpen <sha>^!` needs git, so the preference must not stick
  h.eq(nil, leaked, "the jj adapter preference leaked into the global config")
end)

-- Runs last, once every plugin above has been loaded and driven. vim.deprecated's
-- health report is populated by vim.deprecate() calls made during this session, so it
-- names the plugins that reached for an API Neovim has since removed. Scoped to the
-- plugins we pin to a moving branch, so an unrelated plugin can't fail this.
h.test("no deprecation warnings from branch-pinned plugins", function()
  local watched = { "telescope", "trouble", "neo%-tree", "which%-key", "nvim%-nio", "neotest" }

  -- Sentinel, so a report we failed to read can't pass as a clean one. A removal
  -- version this far out stays soft-deprecated, so it records without warning.
  vim.deprecate("wim.sentinel", "nothing", "0.99")

  vim.cmd "checkhealth vim.deprecated"
  vim.wait(3000, function() return vim.bo.filetype == "checkhealth" end)
  h.eq("checkhealth", vim.bo.filetype, "checkhealth buffer did not open")
  local report = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  vim.cmd "bwipeout!"
  h.assert(report:find("wim.sentinel", 1, true), "sentinel missing, so this report proves nothing:\n" .. report)

  local offenders = {}
  for _, plugin in ipairs(watched) do
    if report:find(plugin) then table.insert(offenders, (plugin:gsub("%%", ""))) end
  end
  h.eq(0, #offenders, "deprecated API use reported for: " .. table.concat(offenders, ", ") .. "\n" .. report)
end)
