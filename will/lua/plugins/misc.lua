local utils = require "will.utils"
local packadd = utils.packadd

---@type lz.n.Spec
return {
  {
    "vim-startuptime",
    cmd = "StartupTime",
    before = function()
      vim.g.startuptime_tries = 50
      vim.g.startuptime_event_width = 0
    end,
  },
  {
    "neorg",
    cmd = "Neorg",
    ft = "norg",
    before = function()
      packadd "lua-utils.nvim"
      packadd "pathlib.nvim"
      packadd "nvim-nio"
      packadd "neorg-interim-ls"
    end,
    after = function()
      require("neorg").setup {
        load = {
          ["core.defaults"] = {},
          ["core.concealer"] = {},
          ["core.journal"] = {
            config = {
              strategy = function(t) return string.lower("" .. os.date("%Y/%W/%Y-%m-%d_%A.norg", os.time(t))) end,
            },
          },
          ["core.dirman"] = { config = { default_workspace = "notes", workspaces = { notes = "~/notes" } } },
          ["external.interim-ls"] = {},
          ["core.esupports.indent"] = {},
          ["core.completion"] = { config = { engine = { module_name = "external.lsp-completion" } } },
        },
      }
    end,
  },
}
