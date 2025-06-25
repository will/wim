-- prevent things from deindenting when typing https://github.com/nvim-treesitter/nvim-treesitter/issues/2566
vim.opt_local.indentkeys:remove { "." }
