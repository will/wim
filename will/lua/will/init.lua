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
  require("will.journal").setup()
end

if utils.sandboxed() then
  -- nvim-treesitter no longer has modules, highlighting is neovim's and indenting
  -- is an indentexpr. Incremental selection is builtin now, see :h v_in
  local function start_treesitter(buf)
    if not vim.api.nvim_buf_is_valid(buf) then return end

    local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)

    -- some ftplugins start treesitter themselves (nvim's own ftplugin/lua.lua does) and
    -- lz.n re-fires FileType after a packadd, so only start what is not already running:
    -- a second highlighter for the same language orphans the first one's tree callbacks
    local active = vim.treesitter.highlighter.active[buf]
    if not (active and lang and active.tree:lang() == lang) then
      if not pcall(vim.treesitter.start, buf) then return end
    end

    -- only languages shipping an indents query, otherwise everything indents to 0
    if lang and vim.treesitter.query.get(lang, "indents") then
      vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("Treesitter", { clear = true }),
    -- deferred by a tick: lz.n packadds `ft` plugins from its own FileType autocmd,
    -- which runs after this one, and vim.treesitter.query.get memoizes a miss for the
    -- session. Starting norg here would pin neorg's queries to nil forever.
    callback = function(args)
      vim.schedule(function() start_treesitter(args.buf) end)
    end,
  })
  utils.after_ui_enter(config)

  utils.packadd "lz.n"
  require("lz.n").load "plugins"

  if vim.fn.argc() == 0 then require "will.alpha" end
else
  config()
end

-- todo: https://github.com/3rd/image.nvim bouncing dvd logo?
