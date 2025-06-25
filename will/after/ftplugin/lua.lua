-- https://vonheikemen.github.io/devlog/tools/neovim-lsp-client-guide/
-- https://aliquote.org/post/neovim-lsp-easy/
-- https://vonheikemen.github.io/devlog/tools/manage-neovim-lsp-client-without-plugins/
-- https://github.com/neovim/nvim-lspconfig/blob/master/lua/lspconfig/server_configurations/lua_ls.lua
vim.lsp.start {
  name = "lua_ls",
  cmd = { "lua-language-server" },
  root_dir = vim.fs.root(0, { ".git" }),
  settings = {
    Lua = {
      diagnostics = { globals = { "vim" } },
      runtime = { version = "LuaJIT", pathStrict = true },
      workspace = {
        -- library = {
        --   "${3rd}/luv/library",
        --   "${3rd}/busted/library",
        --   "${3rd}/luassert/library",
        -- },
        checkThirdParty = false,
      },
      telemetry = { enable = false },
      format = {
        enable = false,
        -- https://github.com/CppCXY/EmmyLuaCodeStyle/blob/master/docs/format_config_EN.md
        defaultConfig = {
          indent_style = "space",
          indent_size = "2",
          quote_style = "double",
          call_arg_parentheses = "remove",
          trailing_table_separator = "always",
        },
      },
    },
  },
}
