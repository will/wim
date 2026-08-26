-- Shared setup for everything that drives this config without a UI: the test runner,
-- nprobe and ndump. Two things here are load-bearing and neither is discoverable.
--
-- lz.n hangs the second half of the config off UIEnter, which never fires headlessly, so
-- until deferred() runs there are no keymaps, no lsp, no none-ls, no blink and no mini.
--
-- Every npins plugin is an `opt` package that lz.n packadds on demand, so a probe asking
-- about a plugin has to load it first or it will truthfully report nothing at all.
local M = {}

--- Let already-scheduled callbacks run. Parts of this config are deliberately a tick
--- late (treesitter starts after lz.n has had its chance to packadd the plugin that
--- ships a language's queries), and leap chains one scheduled hop per round.
---@param rounds integer? Rounds of scheduling to drain (default 1)
function M.settle(rounds)
  for _ = 1, rounds or 1 do
    local ran = false
    vim.schedule(function() ran = true end)
    vim.wait(1000, function() return ran end, 1)
  end
end

--- Fire lz.n's DeferredUIEnter, the stand-in for the UIEnter a headless nvim never gets.
function M.deferred()
  vim.api.nvim_exec_autocmds("User", { pattern = "DeferredUIEnter", modeline = false })
  M.settle()
end

--- Every plugin of ours that can be packadded, named as its directory is, which is also
--- the name its lz.n spec goes by. Neovim ships its own opt packages (netrw, termdebug,
--- matchit) under $VIMRUNTIME and those are not ours to reason about, least of all to
--- load en masse.
---@return string[]
function M.plugin_names()
  local names = {}
  for _, path in ipairs(vim.fn.globpath(vim.o.packpath, "pack/*/opt/*", false, true)) do
    local ours = not vim.startswith(path, vim.env.VIMRUNTIME or "\0")
    if ours and vim.fn.isdirectory(path) == 1 then table.insert(names, vim.fs.basename(path)) end
  end
  table.sort(names)
  return names
end

--- Load plugins through lz.n where it has a spec, so the spec's before/after hooks still
--- run, and plain packadd for the dependencies nothing lazy-loads by name.
---@param names string[]
---@return string[] failures Descriptions of whatever refused to load
function M.load(names)
  local lz = require "lz.n"
  local failures = {}
  for _, name in ipairs(names) do
    local ok, err = pcall(function()
      if lz.lookup(name) then
        lz.trigger_load(name)
      else
        vim.cmd.packadd(name)
      end
    end)
    if not ok then table.insert(failures, name .. ": " .. tostring(err)) end
    M.settle()
  end
  return failures
end

--- Open a file the way a user would, so filetype, treesitter and lsp all get their turn.
--- Three rounds: FileType fires, lz.n packadds whatever that filetype pulls in, then our
--- own deferred treesitter start runs.
---@param path string
function M.open(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  M.settle(3)
end

--- pcall that also catches what pcall cannot: vim.notify at ERROR level and anything
--- thrown from a scheduled or libuv callback land in v:errmsg instead of unwinding, so
--- code can leave broken async work behind and still look like it succeeded.
---@param fn function
---@param rounds integer? Rounds of scheduling to drain before judging (default 0)
---@return boolean ok
---@return string? err
function M.strict_pcall(fn, rounds)
  vim.v.errmsg = ""
  local ok, err = pcall(fn)
  if rounds then M.settle(rounds) end
  if ok and vim.v.errmsg ~= "" then return false, "errors raised during the run: " .. vim.v.errmsg end
  return ok, err ~= nil and tostring(err) or nil
end

return M
