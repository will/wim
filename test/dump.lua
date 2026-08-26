-- The reports behind `ndump`: JSON snapshots of the booted config, so answering "what is
-- bound to this key" or "which plugin is still reaching for a removed API" is a jq query
-- rather than a screenshot of a health buffer.
--
-- Runs as an nprobe payload, so --load and --open have already happened by the time this
-- file is read, and returning a string is enough to get it printed.
local here = debug.getinfo(1, "S").source:sub(2):match "(.*/)" or "test/"
local boot = dofile(here .. "boot.lua")

local reports = {}

--- Every mapping in every mode, global and for the current buffer. With --open, that
--- includes the buffer-local ones an LspAttach installed.
function reports.keymaps()
  local out = {}
  for _, mode in ipairs { "n", "i", "v", "x", "s", "o", "t", "c" } do
    for scope, maps in pairs {
      global = vim.api.nvim_get_keymap(mode),
      buffer = vim.api.nvim_buf_get_keymap(0, mode),
    } do
      for _, map in ipairs(maps) do
        table.insert(out, {
          mode = mode,
          scope = scope,
          lhs = map.lhs,
          desc = map.desc,
          rhs = map.rhs,
          lua = map.callback ~= nil,
        })
      end
    end
  end
  return out
end

--- What is packadded and what is still waiting for its lz.n trigger. `pending` is the
--- interesting column: a plugin that is neither loaded nor pending has no lz.n spec, so
--- only another plugin's packadd will ever bring it in.
function reports.plugins()
  local lz = require "lz.n"
  local loaded = {}
  for _, path in ipairs(vim.opt.runtimepath:get()) do
    loaded[vim.fs.basename(path)] = true
  end

  local out = {}
  for _, name in ipairs(boot.plugin_names()) do
    table.insert(out, { name = name, loaded = loaded[name] == true, pending = lz.lookup(name) ~= nil })
  end
  return out
end

--- Attached clients, plus the real registry of what can attach: this config starts
--- servers from after/ftplugin rather than a server list, so nothing is "configured"
--- until a matching file is open. Use --open to see anything here.
function reports.lsp()
  local clients = {}
  for _, client in ipairs(vim.lsp.get_clients()) do
    table.insert(clients, {
      name = client.name,
      id = client.id,
      root_dir = client.root_dir,
      filetypes = client.config.filetypes,
      buffers = vim.tbl_keys(client.attached_buffers or {}),
      formatting = client:supports_method "textDocument/formatting",
    })
  end

  local starters = {}
  for _, path in ipairs(vim.api.nvim_get_runtime_file("after/ftplugin/*.lua", true)) do
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok and table.concat(lines, "\n"):find("vim.lsp.start", 1, true) then
      table.insert(starters, vim.fs.basename(path))
    end
  end
  table.sort(starters)

  return { clients = clients, started_from = starters }
end

function reports.autocmds()
  local out = {}
  for _, au in ipairs(vim.api.nvim_get_autocmds { event = vim.fn.getcompletion("", "event") }) do
    table.insert(out, {
      event = au.event,
      group = au.group_name,
      pattern = au.pattern,
      desc = au.desc,
      once = au.once,
    })
  end
  return out
end

--- Which grammars exist, and what the current buffer actually got. Highlighting and
--- indenting are separate questions in 0.12: highlighting is neovim's, indenting is an
--- indentexpr, and a language with no indents query keeps whatever set it.
function reports.treesitter()
  -- deduped: nvim ships a handful of the same grammars nvim-treesitter does
  local seen = {}
  for _, path in ipairs(vim.api.nvim_get_runtime_file("parser/*", true)) do
    seen[(vim.fs.basename(path):gsub("%.%a+$", ""))] = true
  end
  local parsers = vim.tbl_keys(seen)
  table.sort(parsers)

  local buf = vim.api.nvim_get_current_buf()
  local current = {
    filetype = vim.bo[buf].filetype,
    indentexpr = vim.bo[buf].indentexpr,
    foldexpr = vim.wo.foldexpr,
  }

  local lang = current.filetype ~= "" and vim.treesitter.language.get_lang(current.filetype) or nil
  if lang then
    current.lang = lang
    current.highlighting = vim.treesitter.highlighter.active[buf] ~= nil
    current.queries = {}
    for _, query in ipairs { "highlights", "indents", "folds", "injections" } do
      current.queries[query] = vim.treesitter.query.get(lang, query) ~= nil
    end
  end

  return { parsers = parsers, buffer = current }
end

--- Deprecated API use, by plugin. vim.deprecated's health report is built from the
--- vim.deprecate() calls made during this session, so loading a plugin is not enough: the
--- offending line has to run. Expect an empty report from --load-all alone, and drive the
--- feature you suspect (`nprobe --load toggleterm.nvim -e 'vim.cmd "ToggleTerm"'`) if you
--- want its warnings counted.
function reports.deprecations()
  -- A sentinel, so an empty report means "nothing deprecated ran" rather than "the report
  -- moved and this parse quietly found nothing". A removal version this far out records
  -- without warning.
  local sentinel = "wim.sentinel"
  vim.deprecate(sentinel, "nothing", "0.99")

  vim.cmd "silent checkhealth vim.deprecated"
  vim.wait(5000, function() return vim.bo.filetype == "checkhealth" end)
  if vim.bo.filetype ~= "checkhealth" then error "the checkhealth buffer never opened" end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  vim.cmd "bwipeout!"

  local out, current, saw_sentinel = {}, nil, false
  for _, line in ipairs(lines) do
    local warning = line:match "WARNING%s+(.+)$"
    if warning then
      if warning:find(sentinel, 1, true) then
        saw_sentinel, current = true, nil
      else
        current = { warning = warning, blames = {} }
        table.insert(out, current)
      end
    elseif current then
      -- the traceback names store paths; the plugin directory is the useful part
      local plugin = line:match "/pack/%w+/opt/([^/]+)/"
      if plugin then current.blames[plugin] = true end
    end
  end
  if not saw_sentinel then error "the sentinel is missing, so this report proves nothing" end

  for _, warning in ipairs(out) do
    warning.blames = vim.tbl_keys(warning.blames)
  end
  return out
end

local name = vim.env.WIM_DUMP_REPORT or ""
local report = reports[name]
if not report then
  local known = vim.tbl_keys(reports)
  table.sort(known)
  io.stderr:write("ndump: no report called '" .. name .. "', try one of: " .. table.concat(known, " ") .. "\n")
  vim.cmd "cq 2"
end

return vim.json.encode(report())
