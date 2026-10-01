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
      -- one source of truth for the path: will.journal reads its settings from in there
      local notes = require("will.journal").config.notes_dir

      require("neorg").setup {
        load = {
          ["core.defaults"] = {},
          -- parsers come from nix, and configuring them needs the removed
          -- nvim-treesitter module api
          ["core.integrations.treesitter"] = { config = { configure_parsers = false } },
          ["core.concealer"] = {},
          ["core.journal"] = {
            config = {
              strategy = function(t) return string.lower("" .. os.date("%Y/%W/%Y-%m-%d_%A.norg", os.time(t))) end,
              -- will.journal writes the skeleton instead: a template is copied verbatim,
              -- so it can neither fill the date in nor stay in step with the sections
              use_template = false,
            },
          },
          ["core.dirman"] = { config = { default_workspace = "notes", workspaces = { notes = notes } } },
          ["external.interim-ls"] = {},
          ["core.esupports.indent"] = {},
          ["core.completion"] = { config = { engine = { module_name = "external.lsp-completion" } } },
        },
      }
    end,
  },
}
