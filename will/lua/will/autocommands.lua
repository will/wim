vim.cmd [[
  augroup _general_settings
    autocmd!
    autocmd FileType qf,help,man,lspinfo nnoremap <silent> <buffer> q :close<CR>
    autocmd TextYankPost * silent!lua require('vim.highlight').on_yank({higroup = 'Visual', timeout = 200})
    autocmd BufWinEnter * :set formatoptions-=cro
    autocmd FileType qf set nobuflisted
  augroup end

  augroup _git
    autocmd!
    autocmd FileType gitcommit setlocal wrap
    autocmd FileType gitcommit setlocal spell
  augroup end

  augroup _markdown
    autocmd!
    autocmd FileType markdown setlocal wrap
    autocmd FileType markdown setlocal spell
  augroup end

  augroup _ruby
    autocmd!
    autocmd FileType ruby setlocal spell
  augroup end

  augroup _auto_resize
    autocmd!
    autocmd VimResized * tabdo wincmd =
  augroup end

  augroup _filetypes
    autocmd!
    autocmd BufRead,BufNewFile *.rbi setfiletype ruby
  augroup end
]]

-- Switch to numbers when while on insert mode or cmd mode, and to relative numbers when in normal mode
vim.cmd [[
   augroup _number_toggle
     autocmd!
     autocmd BufEnter,FocusGained,InsertLeave,WinEnter * if &nu && mode() != 'i' | set rnu   | endif
     autocmd BufLeave,FocusLost,InsertEnter,WinLeave   * if &nu                  | set nornu | endif
     autocmd CmdLineEnter * if &nu | set norelativenumber | endif
     autocmd CmdLineLeave * if &nu | set relativenumber | endif
   augroup END
 ]]

local api = vim.api
local create_autocmd = api.nvim_create_autocmd
local create_augroup = function(name) return api.nvim_create_augroup(name, { clear = true }) end

create_autocmd("FocusGained", {
  pattern = "*",
  callback = function() vim.fn.setreg("p", vim.fn.getreg "+") end,
  group = create_augroup "StashClipboard",
})
