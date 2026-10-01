--- Journal entry helpers on top of neorg's `core.journal`: the skeleton a new entry
--- starts with, and shorthand references rewritten into norg links.
local M = {}

M.config = {
  --- Root of the neorg workspace, which core.dirman is also pointed at, and where the
  --- settings file described below lives.
  notes_dir = "~/notes",

  --- Format of the date a new entry opens with.
  date_format = "%Y-%m-%d %A",

  --- A heading per section, in the order a new entry lays them out. Flagging one
  --- `standup = true` is what puts it in the Slack message, which is why this list
  --- replaced neorg's template file: a template can only be copied verbatim, so its
  --- headings and the ones the standup looked for were two sets of strings with nothing
  --- keeping them in step.
  sections = {
    { "Summary", standup = true },
    { "Log", standup = true },
    "On-call",
    { "TODO", standup = true },
    { "Blockers / Waiting", standup = true },
    "Meetings",
    "Reference",
    "TIL",
  },

  --- Shorthands rewritten into norg links, each a Lua pattern plus either a `%s` URL
  --- template or a function, both fed the pattern's captures (or the whole match, when
  --- it has none). Empty here deliberately: which orgs and trackers to expand is an
  --- employer's business, so it belongs in the settings file, not a public repo.
  links = {},
}

local function resolve(buf) return buf and buf ~= 0 and buf or vim.api.nvim_get_current_buf() end

--- `config.sections` with its shorthand spelled out, so callers never have to care
--- whether an entry was written as a bare name or a table of flags.
--- @return { name: string, standup: boolean }[]
function M.sections()
  local sections = {}
  for _, spec in ipairs(M.config.sections) do
    local name = type(spec) == "string" and spec or spec[1]
    if type(name) ~= "string" then
      vim.notify("Journal: section " .. #sections + 1 .. " has no name", vim.log.levels.ERROR)
    else
      sections[#sections + 1] = { name = name, standup = type(spec) == "table" and spec.standup == true }
    end
  end
  return sections
end

--- The config tables the settings file may write to, under the key it uses for each.
local settings_targets = {
  journal = function() return M.config end,
  standup = function() return require("will.standup").config end,
}

--- Reads `<notes_dir>/journal/wim.lua`, which lives with the notes rather than in this
--- repo so that an employer's org and tracker names stay out of a public one. Keys are
--- overwritten one level deep rather than deep-merged, because `links` and `sections` are
--- lists that a deep merge would splice into the defaults instead of replacing. A key the
--- defaults do not already have is a typo, and says so.
---
--- The file is run as Lua, so it is worth treating like any other code in this config.
--- It returns a table of per-module settings, e.g.
--- ```lua
--- return {
---   journal = {
---     links = {
---       { pattern = "KEY%-%d+", url = "https://tracker.example.com/browse/%s" },
---     },
---     sections = { { "Log", standup = true }, "Reference" },
---   },
--- }
--- ```
--- @return boolean whether a settings file was found and applied
function M.load_settings()
  local path = vim.fs.joinpath(vim.fn.expand(M.config.notes_dir), "journal", "wim.lua")
  if vim.fn.filereadable(path) == 0 then return false end

  local function complain(message) vim.notify(message, vim.log.levels.ERROR, { title = path }) end

  local chunk, syntax_error = loadfile(path)
  if not chunk then
    complain(tostring(syntax_error))
    return false
  end

  local ok, settings = pcall(chunk)
  if not ok then
    complain(tostring(settings))
    return false
  end
  if type(settings) ~= "table" then
    complain("must return a table, got a " .. type(settings))
    return false
  end

  for name, values in pairs(settings) do
    local target = settings_targets[name]
    if not target then
      complain("no module called " .. name .. ", expected journal or standup")
    else
      local config = target()
      for key, value in pairs(values) do
        if config[key] == nil then
          complain(name .. " has no setting called " .. key)
        else
          config[key] = value
        end
      end
    end
  end

  return true
end

--- The entry's own date, read off its filename, so opening yesterday's journal is dated
--- yesterday rather than today. Noon keeps the date clear of DST rounding.
local function entry_time(path)
  local year, month, day = path:match "(%d%d%d%d)-(%d%d)-(%d%d)"
  if not year then return nil end
  return os.time { year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 }
end

--- Lays the date and the section headings into a journal entry that has nothing in it
--- yet. An entry with any content is left alone, so this only ever fires on a new one.
--- @return boolean whether anything was written
function M.scaffold(buf)
  buf = resolve(buf)

  local time = entry_time(vim.api.nvim_buf_get_name(buf))
  if not time then return false end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines > 1 or (lines[1] or "") ~= "" then return false end

  local skeleton = { os.date(M.config.date_format, time), "" }
  for _, section in ipairs(M.sections()) do
    skeleton[#skeleton + 1] = "* " .. section.name
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, skeleton)
  return true
end

local entries = { "today", "yesterday", "tomorrow" }

--- @param when string|nil one of `entries`, defaulting to "today"
function M.open(when)
  when = when or entries[1]
  if not vim.tbl_contains(entries, when) then
    vim.notify("Journal: expected " .. table.concat(entries, ", ") .. ", got " .. when, vim.log.levels.ERROR)
    return
  end

  vim.cmd("Neorg journal " .. when)
  -- deferred: neorg creates and opens the entry from inside that command, and scheduling
  -- keeps this correct even if it ever stops doing so synchronously
  vim.schedule(function()
    if M.scaffold() then pcall(vim.cmd.write) end
  end)
end

--- Byte ranges that must not be rewritten: links that already exist, verbatim spans, and
--- ranged tags, which covers both `@code` blocks and the `@document.meta` header.
local protected = {
  link = true,
  anchor_definition = true,
  anchor_declaration = true,
  verbatim = true,
  inline_math = true,
  inline_comment = true,
  ranged_verbatim_tag = true,
}

local function protected_ranges(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "norg")
  if not ok or not parser then return {} end

  local ranges = {}
  local function walk(node)
    if protected[node:type()] then
      local start_row, start_col, end_row, end_col = node:range()
      for row = start_row, end_row do
        ranges[row] = ranges[row] or {}
        table.insert(ranges[row], {
          from = row == start_row and start_col or 0,
          to = row == end_row and end_col or math.huge,
        })
      end
      return
    end
    for child in node:iter_children() do
      walk(child)
    end
  end

  walk(parser:parse()[1]:root())
  return ranges
end

local function overlaps(ranges, from, to)
  for _, range in ipairs(ranges or {}) do
    if from < range.to and to > range.from then return true end
  end
  return false
end

--- Shorthand references in one line, as byte offsets plus the URL they point at.
local function references(line)
  local found = {}

  for _, rule in ipairs(M.config.links) do
    local init = 1
    while true do
      local match = { line:find(rule.pattern, init) }
      local from, to = match[1], match[2]
      if not from then break end
      init = to + 1

      local captures = vim.list_slice(match, 3)
      if #captures == 0 then captures = { line:sub(from, to) } end

      -- a word character either side means a longer token got clipped, not a reference:
      -- rejects `XKEY-1` for a `KEY-%d+` rule, and the `com/repo#3` buried inside a bare
      -- github URL
      local clipped = line:sub(from - 1, from - 1):match "[%w%-/#]" or line:sub(to + 1, to + 1):match "[%w%-]"
      if not clipped and not overlaps(found, from - 1, to) then
        local url = rule.url
        url = type(url) == "function" and url(unpack(captures)) or url:format(unpack(captures))
        found[#found + 1] = { from = from - 1, to = to, text = line:sub(from, to), url = url }
      end
    end
  end

  return found
end

--- Rewrites every configured shorthand into a norg link, skipping anything already inside
--- a link, a code block or verbatim text.
--- @return boolean whether anything was rewritten
function M.linkify(buf)
  buf = resolve(buf)
  local ranges = protected_ranges(buf)
  local window = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_buf(window) == buf and vim.api.nvim_win_get_cursor(window) or nil
  local changed = false

  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local row = index - 1
    local edits = {}
    for _, reference in ipairs(references(line)) do
      if not overlaps(ranges[row], reference.from, reference.to) then edits[#edits + 1] = reference end
    end
    table.sort(edits, function(a, b) return a.from > b.from end)

    local text, shift = line, 0
    for _, edit in ipairs(edits) do
      local link = "{" .. edit.url .. "}[" .. edit.text .. "]"
      text = text:sub(1, edit.from) .. link .. text:sub(edit.to + 1)
      -- keep the cursor on the same character: everything rewritten ahead of it grew
      if cursor and row == cursor[1] - 1 and edit.to <= cursor[2] then shift = shift + #link - (edit.to - edit.from) end
    end

    if text ~= line then
      vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { text })
      changed = true
      if shift ~= 0 then vim.api.nvim_win_set_cursor(window, { cursor[1], math.min(cursor[2] + shift, #text) }) end
    end
  end

  return changed
end

--- Buffer-local wiring for norg files: linkify on leaving insert mode, and the keymap
--- that copies a standup message out of the buffer.
function M.attach(buf)
  buf = resolve(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)

  vim.api.nvim_create_autocmd("InsertLeave", {
    buffer = buf,
    desc = "Linkify issue and ticket references",
    callback = function()
      -- nothing typed since the last pass, so there is nothing new to rewrite
      if vim.api.nvim_buf_get_changedtick(buf) == tick then return end
      M.linkify(buf)
      tick = vim.api.nvim_buf_get_changedtick(buf)
    end,
  })

  require("will.utils").keymap(
    "n",
    "<localleader>s",
    function() require("will.standup").copy(buf) end,
    "Copy standup to clipboard",
    { buffer = buf }
  )
end

local configured = false

function M.setup()
  -- the keymaps below are `unique`, so a second call would raise rather than no-op the
  -- way requiring a module twice does
  if configured then return end
  configured = true

  M.load_settings()

  local keymap = require("will.utils").keymap

  vim.api.nvim_create_user_command("Journal", function(args) M.open(args.args ~= "" and args.args or nil) end, {
    nargs = "?",
    complete = function() return entries end,
    desc = "Open a journal entry with its date filled in",
  })
  vim.api.nvim_create_user_command("JournalLinkify", function() M.linkify() end, {
    desc = "Rewrite issue and ticket references as norg links",
  })

  keymap("n", "<leader>nj", function() M.open "today" end, "Journal today")
  keymap("n", "<leader>ny", function() M.open "yesterday" end, "Journal yesterday")
  keymap("n", "<leader>nt", function() M.open "tomorrow" end, "Journal tomorrow")
  keymap("n", "<leader>nn", "<cmd>Neorg workspace notes<cr>", "Notes workspace")
end

return M
