local M = {}

M.sandboxed = require("will.sandbox").sandboxed

local function istable(t) return type(t) == "table" end
local added_packs = {}
M.packadd = function(names)
  if not M.sandboxed() then return end

  if not istable(names) then names = { names } end

  for _, name in ipairs(names) do
    if not added_packs[name] then
      vim.cmd.packadd { name, bang = true }
      added_packs[name] = true
    end
  end
end
M.fpackadd = function(name)
  return function() M.packadd(name) end
end

M.after_ui_enter = function(callback)
  vim.api.nvim_create_autocmd("User", {
    pattern = "DeferredUIEnter",
    callback = callback,
  })
end

M.mini_setup = function(plugin, setup)
  M.packadd "mini.nvim"
  require("mini." .. plugin).setup(setup)
end

local map_defaults = { "unique", "noremap", "silent" }
M.keymap = function(mode, lhs, rhs, desc, opt)
  if not opt then opt = {} end
  if desc then opt.desc = desc end
  for _, param in ipairs(map_defaults) do
    if opt[param] == nil then opt[param] = true end
  end

  vim.keymap.set(mode, lhs, rhs, opt)
end

return M
