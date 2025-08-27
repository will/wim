require("will.sandbox").start_sandbox()
local utils = require "will.utils"

vim.g.mapleader = " "
vim.g.maplocalleader = ";"
require "will.options"

if utils.sandboxed() then
  utils.packadd "rose-pine"
  -- vim.api.nvim_create_autocmd('TermResponse', {
  --   once = true,
  --   callback = function()
  --     require("rose-pine").setup {}
  --     vim.cmd.colorscheme "rose-pine"
  --   end
  -- })
  require("rose-pine").setup {}
  vim.cmd.colorscheme "rose-pine"

  -- try to prevent flash of wrong color background before nvim determines the terminals background color
  vim.cmd.highlight "Normal ctermbg=NONE guibg=NONE"
else
  vim.cmd.colorscheme "retrobox"
end

local config = function()
  require "will.keymaps"
  require "will.autocommands"
  require "will.lsp"
  require "will.null_ls"
end

if utils.sandboxed() then
  ---@diagnostic disable-next-line: missing-fields
  require("nvim-treesitter.configs").setup {
    highlight = { enable = true },
    incremental_selection = { enable = true },
    indent = { enable = true },
  }
  utils.after_ui_enter(config)

  utils.packadd "lz.n"
  require("lz.n").load "plugins"

  if vim.fn.argc() == 0 then require "will.alpha" end
else
  config()
end

-- todo: https://github.com/3rd/image.nvim bouncing dvd logo?
