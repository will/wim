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
          ["core.dirman"] = { config = { workspaces = { notes = "~/notes" } } },
          ["external.interim-ls"] = {},
          ["core.completion"] = { config = { engine = { module_name = "external.lsp-completion" } } },
        },
      }
    end,
  },
}
