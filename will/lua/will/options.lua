-- stylua: ignore start
local options = {
  exrc = true,                             -- execute project-local .nvim.lua files
  backup = false,                          -- creates a backup file
  clipboard = "unnamedplus",               -- allows neovim to access the system clipboard
  cmdheight = 0,
  cursorline = true,                       -- highlight the current line
  expandtab = true,                        -- convert tabs to spaces
  foldexpr = "nvim_treesitter#foldexpr()", -- fold by tresitter
  foldlevel = 20,                          --
  foldmethod = "expr",                     --
  guifont = "monospace:h17",               -- the font used in graphical neovim applications
  ignorecase = true,                       -- ignore case in search patterns
  mouse = "a",                             -- allow the mouse to be used in neovim
  number = true,                           -- set numbered lines
  numberwidth = 2,                         -- set number column width to 2 {default 4}
  pumheight = 10,                          -- pop up menu height
  relativenumber = true,                   -- set relative numbered lines
  scrolloff = 8,                           -- keep cursor near middle
  shiftwidth = 2,                          -- the number of spaces inserted for each indentation
  showmode = false,                        -- we don't need to see things like -- INSERT -- anymore
  showtabline = 2,                         -- always show tabs
  sidescrolloff = 8,
  smartcase = true,                        -- smart case search
  smartindent = true,                      -- make indenting smarter again
  spelllang = "en,programming",
  splitbelow = true,                       -- force all horizontal splits to go below current window
  splitkeep = "screen",                    -- keep text on same screen line when opening splits (nvim 0.9)
  splitright = true,                       -- force all vertical splits to go to the right of current window
  swapfile = false,                        -- creates a swapfile
  tabstop = 2,                             -- insert 2 spaces for a tab
  timeoutlen = 200,                        -- time to wait for a mapped sequence to complete (in milliseconds)
  undofile = true,                         -- enable persistent undo
  updatetime = 300,                        -- faster completion (4000ms default)
  wrap = false,                            -- display lines as one long line
  writebackup = false,                     -- if a file is being edited by another program (or was written to file while editing with another program), it is not allowed to be edited
}
-- stylua: ignore end

-- c	don't give |ins-completion-menu| messages.  For example,
--   "-- XXX completion (YYY)", "match 1 of 2", "The only match",
--   "Pattern not found", "Back at original", etc.
-- I  vim intro
-- C  scanning for ins-completion , like "scanning tags"
vim.opt.shortmess:append { c = true, I = true, C = true }

for k, v in pairs(options) do
  vim.opt[k] = v
end

vim.opt.fillchars = {
  vert = "║",
  horiz = "═",
  horizup = "╩",
  horizdown = "╦",
  vertleft = "╣",
  vertright = "╠",
  verthoriz = "╬",
  eob = " ",
}

-- speed up built-in ftplugin/ruby.vim by 50ms
vim.g.ruby_path = {}

vim.cmd "set whichwrap+=<,>,[,],h,l"
vim.cmd [[set iskeyword+=-]] -- add hyphen to same word list
vim.cmd [[set formatoptions-=cro]] -- TODO: this doesn't seem to work

-- per project spelling
vim.cmd [[set spellfile=.en.utf-8.add]]
