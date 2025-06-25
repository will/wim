local utils = require "will.utils"
if not utils.sandboxed() then return end

local packadd = utils.packadd
packadd "none-ls.nvim"
packadd "plenary.nvim"
local null_ls = require "null-ls"
local format = null_ls.builtins.formatting

-- https://github.com/nvimtools/none-ls.nvim/blob/main/doc/BUILTIN_CONFIG.md
-- https://github.com/nvimtools/none-ls.nvim/blob/main/doc/BUILTINS.md

null_ls.setup {
  sources = {
    format.stylua,
    format.crystal_format,
  },
}
