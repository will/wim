local set = require("will.utils").keymap
local nmap = function(lhs, rhs, desc, opt) set("n", lhs, rhs, desc, opt) end

-- Modes
--   normal_mode = "n",
--   insert_mode = "i",
--   visual_mode = "v",
--   visual_block_mode = "x",
--   term_mode = "t",
--   command_mode = "c",

local leader = function(key, cmd, desc) nmap("<leader>" .. key, cmd, desc) end

-- Normal --

set("n", "<bs>", "<cmd>nohlsearch<cr>", "Clear search")

leader("q", "<cmd>q!<CR>", "Quit")
leader("w", "<cmd>w!<CR>", "Save")
leader("c", function() require("mini.bufremove").delete(0, false) end, "Close Buffer")

-- Better window navigation
nmap("<C-h>", "<C-w>h")
--set("n", "<C-j>", "<C-w>j")
nmap("<C-k>", "<C-w>k")
nmap("<C-l>", "<C-w>l", nil, { unique = false })

-- Resize with arrows
nmap("<C-Up>", ":resize -2<CR>")
nmap("<C-Down>", ":resize +2<CR>")
nmap("<C-Left>", ":vertical resize -2<CR>")
nmap("<C-Right>", ":vertical resize +2<CR>")

-- Navigate buffers
--set("n","<S-l>", ":bnext<CR>")
--set("n","<S-h>", ":bprevious<CR>")
nmap("<tab>", ":silent! bnext<CR>")
nmap("<S-tab>", ":silent! bprevious<CR>")

-- keep search centered
nmap("n", "nzzzv")
nmap("N", "Nzzzv")

-- have marks go to the actual character instead of first non whitespace
nmap("'", "`")

-- Insert --
-- Press jk fast to enter insert mode
set("i", "jk", "<ESC>")

-- add more undo points while typing
for _, v in pairs { ".", ",", "!", "?" } do
  set("i", v, v .. "<c-g>u")
end

-- Visual --
-- Stay in indent mode
set("v", "<", "<gv")
set("v", ">", ">gv")

set("v", "p", '"_dp')

-- paste overwrite selection
-- Visual Block --
-- Move text up and down
set("x", "J", ":move '>+1<CR>gv-gv")
set("x", "K", ":move '<-2<CR>gv-gv")
--set("x", "<A-j>", ":move '>+1<CR>gv-gv")
--set("x", "<A-k>", ":move '<-2<CR>gv-gv")

-- add some RSI - readline style bindings
-- mappings from https://github.com/tpope/vim-rsi/blob/master/plugin/rsi.vim
set("i", "<C-A>", "<C-O>^")
set("c", "<C-A>", "<Home>")
set("i", "<C-E>", "<C-O>$")

-- prevent stray clicks
set("i", "<LeftMouse>", "<Nop>")
