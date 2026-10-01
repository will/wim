-- Journal tests: the new-entry skeleton, reference linkifying, and the standup message.
--
-- These all go through a real norg buffer rather than a scratch one. Everything here
-- reads the treesitter tree, and the norg parser's queries only arrive once lz.n has
-- packadded neorg off FileType, so h.open is the only path that gets the ordering right.
local h = dofile "test/helpers.lua"

local dir = vim.fn.tempname() .. "/journal"
vim.fn.mkdir(dir, "p")

--- Write a norg file and open it the way a user would.
---@param name string
---@param lines string[]
---@return integer buf
local function open_norg(name, lines)
  local path = dir .. "/" .. name
  vim.fn.writefile(lines, path)
  h.open(path)
  h.eq("norg", vim.bo.filetype, name .. " did not become a norg buffer")
  return vim.api.nvim_get_current_buf()
end

--- Swaps in a section list for the duration of `fn`, since the defaults are the author's
--- own and a test that asserted against them would be a test of personal taste.
local function with_sections(specs, fn)
  local journal = require "will.journal"
  local sections = journal.config.sections
  journal.config.sections = specs

  local ok, err = pcall(fn)
  journal.config.sections = sections
  if not ok then error(err) end
end

--- 2022-03-24 was a Thursday, which is the whole point: the weekday is computed from the
--- date rather than written down, so a wrong one would be caught here.
h.test("a new entry is scaffolded with its own date and the configured sections", function()
  local buf = open_norg("2022-03-24_thursday.norg", {})

  with_sections({ { "Summary", standup = true }, "Reference" }, function()
    h.assert(require("will.journal").scaffold(buf), "scaffold reported writing nothing")
    h.eq(
      table.concat({ "2022-03-24 Thursday", "", "* Summary", "* Reference" }, "\n"),
      table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"),
      "wrong skeleton"
    )
  end)
  vim.cmd "bwipeout!"
end)

-- Scaffolding is for a brand new entry. Yesterday's, reopened, has to keep what is in it
-- rather than have a fresh skeleton laid over the top.
h.test("an entry that already has content is not scaffolded", function()
  local buf = open_norg("2022-03-24_written.norg", { "* Summary", "   - already here" })
  h.eq(false, require("will.journal").scaffold(buf), "an entry with content was scaffolded")
  h.eq("* Summary", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1], "the entry was overwritten")
  vim.cmd "bwipeout!"
end)

-- A norg file with no date in its name is not a journal entry, so it has no date to be
-- scaffolded with and must be left alone rather than given today's.
h.test("a dateless norg file is not scaffolded", function()
  local buf = open_norg("scratch.norg", {})
  h.eq(false, require("will.journal").scaffold(buf), "a dateless file was scaffolded")
  vim.cmd "bwipeout!"
end)

-- A bare string and a flagged table mean the same thing bar the flag, and every caller
-- reads the list through this rather than handling both shapes itself.
h.test("section shorthand and the flagged form normalise the same way", function()
  with_sections({ "Plain", { "Flagged", standup = true } }, function()
    local flat = {}
    for _, section in ipairs(require("will.journal").sections()) do
      flat[#flat + 1] = section.name .. "=" .. tostring(section.standup)
    end
    h.eq("Plain=false,Flagged=true", table.concat(flat, ","), "sections did not normalise")
  end)
end)

--- The link rules the real config reads from the notes directory, inlined so these tests
--- do not depend on a settings file being present.
local function with_links(fn)
  local journal = require "will.journal"
  local links = journal.config.links

  journal.config.links = {
    {
      pattern = "([%w][%w%._%-/]*)#(%d+)",
      url = function(repo, number)
        if not repo:find "/" then repo = "an-org/" .. repo end
        return ("https://github.com/%s/pull/%s"):format(repo, number)
      end,
    },
    { pattern = "KEY%-%d+", url = "https://tracker.example.com/browse/%s" },
  }

  local ok, err = pcall(fn)
  journal.config.links = links
  if not ok then error(err) end
end

h.test("references become norg links, and anything already linked is left alone", function()
  local buf = open_norg("2022-03-24_linkify.norg", {
    "@document.meta",
    "title: widget#999",
    "@end",
    "",
    "* Today",
    "   - Landed widget#324 and other-org/thing#12",
    "   - Ticket KEY-3279257 blocks it",
    "   - Already {https://github.com/an-org/widget/pull/7}[widget#7]",
    "   - Verbatim `widget#111`",
    "   - Not refs: XKEY-1 KEY-1x UTF-8 GPT-4",
    "",
    "   @code sh",
    "   curl example.com/widget#555",
    "   @end",
  })

  with_links(function()
    h.assert(require("will.journal").linkify(buf), "linkify reported no rewrite")
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local github = "https://github.com/an-org/widget/pull/"

    h.eq("title: widget#999", lines[2], "@document.meta was rewritten")
    h.eq(
      "   - Landed {"
        .. github
        .. "324}[widget#324] and {https://github.com/other-org/thing/pull/12}[other-org/thing#12]",
      lines[6],
      "a bare reference, or an explicitly-orged one, did not linkify"
    )
    h.eq(
      "   - Ticket {https://tracker.example.com/browse/KEY-3279257}[KEY-3279257] blocks it",
      lines[7],
      "a tracker key did not linkify"
    )
    h.eq("   - Already {" .. github .. "7}[widget#7]", lines[8], "an existing link was linkified again")
    h.eq("   - Verbatim `widget#111`", lines[9], "a verbatim span was rewritten")
    h.eq("   - Not refs: XKEY-1 KEY-1x UTF-8 GPT-4", lines[10], "a false positive was linkified")
    h.eq("   curl example.com/widget#555", lines[13], "a @code block was rewritten")

    -- a second pass must be a no-op, since InsertLeave runs this over the whole buffer
    h.eq(false, require("will.journal").linkify(buf), "linkify was not idempotent")
  end)
  vim.cmd "bwipeout!"
end)

-- With no settings file there are no rules, so nothing in a norg buffer is rewritten and
-- this repo carries no opinion about anybody's github org.
h.test("no configured links means no rewriting", function()
  local journal = require "will.journal"
  local links = journal.config.links
  journal.config.links = {}

  local buf = open_norg("2022-03-24_norules.norg", { "* Today", "   - Landed widget#324 and KEY-1 today" })
  local ok, err = pcall(function()
    h.eq(false, journal.linkify(buf), "something was rewritten with no rules configured")
    h.eq("   - Landed widget#324 and KEY-1 today", vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1], "line changed")
  end)

  journal.config.links = links
  vim.cmd "bwipeout!"
  if not ok then error(err) end
end)

-- linkify runs on InsertLeave, with the cursor sitting just past what was typed, and the
-- link it inserts is longer than the reference it replaces.
h.test("linkify keeps the cursor on the same character", function()
  local buf = open_norg("2022-03-24_cursor.norg", { "* Today", "   - Landed widget#324 today" })
  -- the space just after the reference, found rather than counted so a reworded fixture
  -- cannot quietly move it
  local column = vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]:find " today" - 1
  vim.api.nvim_win_set_cursor(0, { 2, column })

  with_links(function()
    require("will.journal").linkify(buf)
    local line = vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]
    local moved = vim.api.nvim_win_get_cursor(0)[2]
    h.eq(" today", line:sub(moved + 1), "the cursor did not follow the text it was on")
  end)
  vim.cmd "bwipeout!"
end)

h.test("the standup message takes the flagged sections and drops the empty ones", function()
  -- the shape will.journal.scaffold actually writes: the date as a bare line above the
  -- first heading, and the sections themselves at level one
  local buf = open_norg("2022-03-24_standup.norg", {
    "2022-03-24 Thursday",
    "",
    "* Yesterday",
    "   - (x) Shipped it",
    "",
    "* Today",
    "   - ( ) Next thing",
    "",
    "* Blockers",
    "",
    "* Private",
    "   - not for slack",
  })

  -- "Private" is in the entry but unflagged, and "Absent" is flagged but not in the entry
  local specs = {
    { "Yesterday", standup = true },
    { "Today", standup = true },
    { "Blockers", standup = true },
    { "Absent", standup = true },
    "Private",
  }

  with_sections(specs, function()
    local message = require("will.standup").copy(buf)
    -- stylua: ignore
    h.eq(table.concat({
      "*2022-03-24 Thursday*",
      "",
      "*Yesterday*",
      "• ☑ Shipped it",
      "",
      "*Today*",
      "• ☐ Next thing",
    }, "\n"), message, "wrong standup message")
    h.assert(not message:find "Blockers", "an empty section was emitted as a bare header")
    h.assert(not message:find "Private", "an unflagged section was included")
  end)
  vim.cmd "bwipeout!"
end)

-- The date rides along with the sections rather than leading the message on its own, so
-- a scaffolded but unwritten entry still reports nothing to copy.
h.test("an entry with only its date copies nothing", function()
  local buf = open_norg("2022-03-24_untouched.norg", { "2022-03-24 Thursday", "", "* Summary", "* Log" })

  with_sections({ { "Summary", standup = true }, { "Log", standup = true } }, function()
    local notified
    local notify = vim.notify
    vim.notify = function(message) notified = message end
    local copied = require("will.standup").copy(buf)
    vim.notify = notify

    h.eq(nil, copied, "an empty entry copied something")
    h.assert(notified and notified:find "Nothing to copy", "no warning: " .. tostring(notified))
  end)
  vim.cmd "bwipeout!"
end)

h.test("the standup message translates norg markup and links for slack", function()
  local buf = open_norg("2022-03-24_markup.norg", {
    "* 2022-03-24 Thursday",
    "",
    "** Today",
    "   - (x) Kept *bold*, made /italic/ and -struck- and `code`",
    "   - ( ) Reviewed {https://github.com/an-org/widget/pull/324}[widget#324]",
    "   -- nested under it",
    "   - ( ) Bare {https://example.com} and a heading {* Today}[link]",
    "   ~ first",
    "   ~ second",
  })

  with_sections({ { "Today", standup = true } }, function()
    -- stylua: ignore
    h.eq(table.concat({
      "*Today*",
      "• ☑ Kept *bold*, made _italic_ and ~struck~ and `code`",
      "• ☐ Reviewed [widget#324](https://github.com/an-org/widget/pull/324)",
      "    ◦ nested under it",
      "• ☐ Bare https://example.com and a heading link",
      "1. first",
      "2. second",
    }, "\n"), require("will.standup").copy(buf), "wrong slack formatting")
  end)
  vim.cmd "bwipeout!"
end)

-- The settings file is what keeps an employer's org and tracker names out of this public
-- repo, so it has to actually reach both modules' config tables.
h.test("settings are read from the notes directory", function()
  local journal = require "will.journal"
  local standup = require "will.standup"
  local saved = { journal.config.notes_dir, journal.config.links, journal.config.sections, standup.config.indent }

  local notes = vim.fn.tempname()
  vim.fn.mkdir(notes .. "/journal", "p")
  journal.config.notes_dir = notes

  local ok, err = pcall(function()
    h.eq(false, journal.load_settings(), "a missing settings file was reported as applied")

    vim.fn.writefile({
      "return {",
      "  journal = {",
      "    links = { { pattern = 'ZZZ%-%d+', url = 'https://example.test/%s' } },",
      "    sections = { { 'Only This', standup = true } },",
      "  },",
      "  standup = { indent = '  ' },",
      "}",
    }, notes .. "/journal/wim.lua")

    h.assert(journal.load_settings(), "the settings file was not applied")
    h.eq(1, #journal.config.links, "the link rule did not arrive")
    h.eq("ZZZ%-%d+", journal.config.links[1].pattern, "wrong link rule")
    h.eq("  ", standup.config.indent, "settings did not reach the standup module")

    -- the defaults are a list, so a merge that spliced rather than replaced would leave
    -- the author's own sections in alongside
    local names = vim.tbl_map(function(section) return section.name end, journal.sections())
    h.eq("Only This", table.concat(names, ","), "sections were spliced instead of replaced")

    -- a typo must be reported rather than silently doing nothing
    vim.fn.writefile({ "return { journal = { linkz = {} } }" }, notes .. "/journal/wim.lua")
    local notified
    local notify = vim.notify
    vim.notify = function(message) notified = message end
    journal.load_settings()
    vim.notify = notify
    h.assert(notified and notified:find "linkz", "an unknown setting was accepted: " .. tostring(notified))
  end)

  journal.config.notes_dir, journal.config.links = saved[1], saved[2]
  journal.config.sections, standup.config.indent = saved[3], saved[4]
  vim.fn.delete(notes, "rf")
  if not ok then error(err) end
end)

h.test("journal commands and keymaps are registered", function()
  h.deferred() -- will.journal.setup runs with the rest of the deferred config

  local commands = vim.api.nvim_get_commands {}
  for _, name in ipairs { "Journal", "JournalLinkify" } do
    h.assert(commands[name], ":" .. name .. " is not defined")
  end

  for _, lhs in ipairs { "<leader>nj", "<leader>ny", "<leader>nt", "<leader>nn" } do
    local keys = vim.keycode(lhs)
    h.assert(vim.fn.maparg(keys, "n") ~= "", lhs .. " is not mapped")
  end
end)

-- The whole reason :Journal exists rather than :Neorg journal today. neorg creates and
-- opens the entry from inside its own command and puts nothing in it, so this is what
-- proves the skeleton lands on the buffer the command left us in and reaches disk.
h.test("the Journal command scaffolds the entry it creates", function()
  h.deferred()
  h.eq(0, #h.load { "neorg" }, "neorg failed to load")

  local modules = require "neorg.core.modules"
  local dirman = modules.get_module "core.dirman"
  h.assert(dirman, "core.dirman is not loaded")

  -- a workspace of our own: the real one is the notes the user is keeping
  local workspace = vim.fn.tempname()
  vim.fn.mkdir(workspace .. "/journal", "p")
  h.assert(dirman.add_workspace("wimtest", workspace), "could not add a test workspace")

  local config = modules.get_module_config "core.journal"
  local previous = config.workspace
  config.workspace = "wimtest"

  local ok, err = pcall(function()
    with_sections({ "Summary" }, function()
      vim.cmd "Journal"
      h.settle(3)

      local path = vim.api.nvim_buf_get_name(0)
      h.assert(path:find(os.date "%Y-%m-%d", 1, true), "Journal did not land in today's entry: " .. path)

      local expected = { os.date "%Y-%m-%d %A", "", "* Summary" }
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      h.eq(table.concat(expected, "\n"), table.concat(lines, "\n"), "wrong buffer contents")
      h.eq(false, vim.bo.modified, "the entry was left unsaved")
      h.eq(table.concat(expected, "\n"), table.concat(vim.fn.readfile(path), "\n"), "the skeleton never reached disk")
    end)
  end)

  config.workspace = previous
  pcall(vim.cmd, "bwipeout!")
  vim.fn.delete(workspace, "rf")
  if not ok then error(err) end
end)

-- lz.n re-fires FileType after it packadds neorg, so after/ftplugin/norg.lua is sourced
-- twice for the first norg buffer of the session. Both the keymap (which is `unique`) and
-- the InsertLeave autocommand would object.
h.test("the norg ftplugin attaches once per buffer", function()
  local buf = open_norg("2022-03-24_attach.norg", { "* Today" })
  h.assert(vim.b[buf].will_norg_attached, "the ftplugin did not attach")

  local failures = h.load { "neorg" } -- a no-op if already loaded, which is the point
  h.eq(0, #failures, "neorg failed to load: " .. vim.inspect(failures))

  local attached = pcall(vim.cmd.runtime, "after/ftplugin/norg.lua")
  h.assert(attached, "re-sourcing the ftplugin raised, so a second FileType would error")

  local maps = vim.fn.maparg(vim.keycode "<localleader>s", "n", false, true)
  h.assert(maps.buffer == 1, "<localleader>s is not buffer-local: " .. vim.inspect(maps))

  local autocmds = vim.api.nvim_get_autocmds { event = "InsertLeave", buffer = buf }
  h.eq(1, #autocmds, "the linkify autocommand was registered more than once")
  vim.cmd "bwipeout!"
end)

vim.fn.delete(vim.fs.dirname(dir), "rf")
