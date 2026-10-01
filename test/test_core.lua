-- Core config smoke tests
-- Tests that the config bootstraps correctly
local h = dofile "test/helpers.lua"

h.test("config bootstrapped", function()
  h.assert(package.loaded["will"], "will was never required")
  h.assert(package.loaded["will.options"], "will.options not loaded")
  h.assert(require("will.utils").sandboxed(), "not running the flake's own config")
  h.eq(" ", vim.g.mapleader, "mapleader not set")
  h.eq(";", vim.g.maplocalleader, "maplocalleader not set")
  h.eq("expr", vim.o.foldmethod, "will.options did not apply")
end)

-- The reason 'clipboard' is empty rather than unnamedplus: that would send deletes to the
-- system clipboard as well as yanks, so a `dd` in here would throw away whatever had been
-- copied in the browser. Deleted text still has to come back with `p` though, which is
-- the other half of the bargain.
h.test("yanks reach the system clipboard, deletes stay in vim", function()
  h.deferred() -- the yank publisher is registered with the rest of the deferred config
  h.eq("", vim.o.clipboard, "'clipboard' is set, so deletes would reach the system clipboard")

  -- Reading '+' through the configured OSC 52 provider would ask the terminal a question
  -- that headless nvim has nothing to answer with, and stall ten seconds before giving up
  -- empty. An in-memory provider keeps the register real while staying local.
  local provider = vim.g.clipboard
  local store = {}
  vim.g.clipboard = {
    name = "test",
    copy = { ["+"] = function(lines, regtype) store[1] = { lines, regtype } end, ["*"] = function() end },
    paste = { ["+"] = function() return store[1] or { { "" }, "v" } end, ["*"] = function() end },
  }

  vim.cmd "tabnew"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "yanked line", "doomed line" })

  local ok, err = pcall(function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd "normal! yy"
    h.eq("yanked line\n", vim.fn.getreg "+", "a yank did not reach the clipboard")

    vim.cmd "normal! jdd"
    h.eq("yanked line\n", vim.fn.getreg "+", "a delete reached the clipboard and clobbered the yank")
    h.eq("doomed line\n", vim.fn.getreg '"', "the deleted text is not there to paste back")

    vim.cmd "normal! p"
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    h.eq("yanked line,doomed line", table.concat(lines, ","), "the delete did not paste back")

    -- an explicitly named register is a deliberate choice to go somewhere else
    vim.cmd 'normal! gg"ayy'
    h.eq("yanked line\n", vim.fn.getreg "+", '"ayy was published to the clipboard')
  end)

  vim.cmd "tabclose!"
  vim.g.clipboard = provider
  if not ok then error(err) end
end)

h.test("colorscheme set", function() h.assert(vim.g.colors_name ~= nil, "no colorscheme set") end)

h.test("lz.n lazy loader available", function() h.require_ok "lz.n" end)

-- lz.n only fires this on UIEnter, which never happens headlessly, so everything
-- hanging off it (keymaps, lsp, none-ls, blink, mini) needs a nudge
h.test("deferred config loads", function()
  vim.api.nvim_exec_autocmds("User", { pattern = "DeferredUIEnter", modeline = false })
  h.assert(package.loaded["will.keymaps"], "will.keymaps not loaded")
  h.assert(package.loaded["will.lsp"], "will.lsp not loaded")
  h.assert(package.loaded["will.autocommands"], "will.autocommands not loaded")
end)

-- git signs render through 'statuscolumn' now, which is evaluated for every screen
-- line in every window, including before gitsigns has been lazy-loaded
h.test("statuscolumn survives gitsigns being lazy loaded", function()
  h.assert(vim.o.statuscolumn:find("git_statuscolumn", 1, true), "gitsigns not wired in: " .. vim.o.statuscolumn)

  local function render()
    return vim.api.nvim_eval_statusline(vim.o.statuscolumn, {
      winid = vim.api.nvim_get_current_win(),
      use_statuscol_lnum = 1,
    }).str
  end

  local loaded = package.loaded.gitsigns
  package.loaded.gitsigns = nil
  local ok_before, before = pcall(render)
  package.loaded.gitsigns = loaded
  h.assert(ok_before, "statuscolumn errored before gitsigns loaded: " .. tostring(before))

  require("lz.n").trigger_load "gitsigns.nvim"
  local ok_after, after = pcall(render)
  h.assert(ok_after, "statuscolumn errored after gitsigns loaded: " .. tostring(after))
  h.eq(false, require("gitsigns.config").config.signcolumn, "gitsigns should leave the sign column to diagnostics")

  -- a hand-written 'statuscolumn' replaces the number column too, so %l has to keep
  -- rendering the hybrid numbering this config asks for: absolute on the cursor line,
  -- relative everywhere else
  vim.cmd "new"
  local scratch = vim.api.nvim_get_current_buf()
  vim.bo[scratch].buftype = "nofile"
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "one", "two", "three", "four", "five" })
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  local numbers = {}
  for lnum = 2, 4 do
    numbers[#numbers + 1] = vim.api
      .nvim_eval_statusline(vim.o.statuscolumn, {
        winid = vim.api.nvim_get_current_win(),
        use_statuscol_lnum = lnum,
      }).str
      :match "%d+"
  end
  vim.cmd "close"
  vim.api.nvim_buf_delete(scratch, { force = true })
  h.eq("1,3,1", table.concat(numbers, ","), "hybrid line numbers lost")
end)

-- These used to be set per LspAttach behind `if not package.loaded.noice`. noice loads a
-- tick into startup, so the first attach got them and no later one did, leaving every
-- buffer after the first with no <C-s> at all (K only looked fine because
-- vim.lsp._set_defaults quietly installs its own borderless one).
h.test("lsp hover and signature help keep their borders once noice has loaded", function()
  require("lz.n").trigger_load "noice.nvim"
  h.assert(package.loaded.noice, "noice did not load, so this proves nothing")

  vim.cmd "enew"
  local ok, err = pcall(function()
    -- non-empty is exactly what stops vim.lsp._set_defaults claiming K on attach
    h.assert(vim.fn.maparg("K", "n", false, false) ~= "", "K is unmapped, so LspAttach would claim it")

    local calls = {}
    local hover, signature = vim.lsp.buf.hover, vim.lsp.buf.signature_help
    vim.lsp.buf.hover = function(opts) calls.hover = opts end
    vim.lsp.buf.signature_help = function(opts) calls.signature = opts end
    for _, m in ipairs { { "K", "n", "hover" }, { "<C-s>", "i", "signature" }, { "<C-s>", "s", "signature" } } do
      local map = vim.fn.maparg(m[1], m[2], false, true)
      h.assert(map.callback, m[1] .. " is not mapped in " .. m[2] .. " mode")
      map.callback()
    end
    vim.lsp.buf.hover, vim.lsp.buf.signature_help = hover, signature

    h.eq("rounded", (calls.hover or {}).border, "K lost its rounded border")
    h.eq("rounded", (calls.signature or {}).border, "<C-s> lost its rounded border")
  end)

  vim.cmd "bwipeout!"
  if not ok then error(err) end
end)

h.test("none-ls formatting sources", function()
  local names = vim.tbl_map(function(s) return s.name end, require("null-ls.sources").get_all())
  for _, want in ipairs { "stylua", "crystal_format" } do
    h.assert(vim.tbl_contains(names, want), want .. " source missing, have " .. vim.inspect(names))
  end
end)

-- Format-on-save is the LSP's, and an LSP that cannot find its formatter fails quietly:
-- nixd answers "formatting nixfmt command exited with 65280" and the buffer is left
-- alone. So the wrapper has to carry every one of these itself, not borrow them from
-- whatever happens to be in the user's profile.
h.test("the formatters our LSPs shell out to are on the wrapper's PATH", function()
  for _, exe in ipairs { "nixd", "nixfmt", "lua-language-server", "stylua" } do
    h.eq(1, vim.fn.executable(exe), exe .. " is missing, so its format-on-save does nothing")
  end
end)

h.test("treesitter available", function() h.require_ok "nvim-treesitter" end)

h.test(
  "treesitter lua parser",
  function() h.assert(pcall(vim.treesitter.language.add, "lua"), "lua parser missing") end
)

h.test(
  "treesitter nix parser",
  function() h.assert(pcall(vim.treesitter.language.add, "nix"), "nix parser missing") end
)

h.test("treesitter highlights and indents a buffer", function()
  vim.cmd.edit "test/fixtures/sample.lua"
  local buf = vim.api.nvim_get_current_buf()
  h.settle() -- the FileType handler starts treesitter a tick late, see will.init
  h.eq("lua", vim.bo[buf].filetype)
  h.assert(vim.treesitter.highlighter.active[buf], "no treesitter highlighter attached")
  h.assert(vim.bo[buf].indentexpr:find "nvim%-treesitter", "treesitter indentexpr not set")
  vim.cmd "bwipeout!"
end)

-- neorg ships the norg queries and lz.n only packadds neorg from its own FileType
-- autocmd, so treesitter has to start after that has run: vim.treesitter.query.get
-- memoizes a miss, and one miss leaves norg unhighlighted for the whole session. Only
-- the normal open path can catch that, so no pre-loading here.
h.test("treesitter highlights norg, whose queries arrive with the plugin", function()
  h.assert(not package.loaded.neorg, "neorg was already loaded, so this proves nothing")

  vim.cmd.edit "test/fixtures/sample.norg"
  local buf = vim.api.nvim_get_current_buf()
  h.eq("norg", vim.bo[buf].filetype)
  h.settle(4)

  local ok, err = pcall(function()
    h.assert(vim.treesitter.query.get("norg", "highlights"), "the norg highlights query resolved to nil")
    h.assert(vim.treesitter.highlighter.active[buf], "no treesitter highlighter attached to the norg buffer")

    local captures = 0
    for col = 0, #vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] - 1 do
      captures = captures + #vim.inspect_pos(buf, 0, col).treesitter
    end
    h.assert(captures > 0, "nothing highlighted on line 1")

    -- neorg's concealer draws the heading and list icons; it runs off its own autocmds
    local function conceals()
      local n = 0
      for name, ns in pairs(vim.api.nvim_get_namespaces()) do
        if name:find "neorg" then n = n + #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) end
      end
      return n
    end
    vim.wait(5000, function() return conceals() > 0 end, 50)
    h.assert(conceals() > 0, "no neorg concealer extmarks")

    -- norg ships no indents query, so it has to keep neorg's own indentexpr
    h.eq(nil, vim.treesitter.query.get("norg", "indents"), "norg gained an indents query")
    h.assert(vim.bo[buf].indentexpr:find "neorg", "norg lost neorg's indentexpr: " .. vim.bo[buf].indentexpr)
  end)

  vim.cmd "bwipeout!"
  if not ok then error(err) end
end)

-- 'foldexpr' used to name a Vimscript function nvim-treesitter's main branch deleted, so
-- every fold evaluation raised E117 config-wide. lua and norg only looked healthy
-- because their ftplugins set a window-local 'foldexpr' of their own.
h.test("treesitter folding computes fold levels", function()
  -- Real files in a temp dir, not scratch buffers: 'foldexpr' has to be evaluated after
  -- the buffer has a parser, and only the normal open path gets that ordering right.
  -- stylua: ignore
  local samples = {
    { "fold.lua",  { "local function outer()", "  if true then", "    return 1", "  end", "end" } },
    { "fold.nix",  { "{", "  a = {", "    b = 1;", "  };", "}" } },
    { "fold.rb",   { "class Foo", "  def bar", "    1", "  end", "end" } },
    { "fold.md",   { "# one", "text", "text", "## two", "more", "more" } },
    { "fold.norg", { "* Heading one", "  text", "  text", "** Heading two", "   more", "   more" } },
  }

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  vim.cmd "tabnew"
  local tab = vim.api.nvim_get_current_tabpage()
  local ok, err = pcall(function()
    for _, sample in ipairs(samples) do
      local name, lines = sample[1], sample[2]
      vim.fn.writefile(lines, dir .. "/" .. name)
      vim.cmd.edit(dir .. "/" .. name)
      local ft = vim.bo.filetype
      h.settle(4)

      -- lua and norg have ftplugins that set this window-locally; every other filetype
      -- inherits the global, which is how a dead global went unnoticed
      h.eq("v:lua.vim.treesitter.foldexpr()", vim.wo.foldexpr, ft .. " is not folding by treesitter")
      h.assert(pcall(vim.cmd, "normal! zM"), ft .. ": zM raised")
      h.assert(pcall(vim.cmd, "normal! zR"), ft .. ": zR raised")

      local levels, deepest = {}, 0
      for lnum = 1, #lines do
        levels[lnum] = vim.fn.foldlevel(lnum)
        deepest = math.max(deepest, levels[lnum])
      end
      h.assert(deepest > 1, ft .. " did not fold its nesting: " .. vim.inspect(levels))

      vim.cmd "bwipeout!"
    end

    -- a filetype with no parser must not raise, it just never folds
    vim.cmd "enew"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "  two", "    three" })
    vim.bo.filetype = "wimhasnoparserforthis"
    h.settle()
    h.eq(0, vim.fn.foldlevel(2), "a parserless buffer reported a fold level")
    h.assert(pcall(vim.cmd, "normal! zR"), "zR raised in a parserless buffer")
    vim.cmd "bwipeout!"

    h.eq("v:lua.vim.treesitter.foldexpr()", vim.o.foldexpr, "the global foldexpr is not neovim's own")
  end)

  -- wiping the last buffer in the tab already closes it
  if vim.api.nvim_tabpage_is_valid(tab) and #vim.api.nvim_list_tabpages() > 1 then
    vim.api.nvim_set_current_tabpage(tab)
    vim.cmd "tabclose!"
  end
  vim.fn.delete(dir, "rf")
  if not ok then error(err) end
end)
