local utils = require "will.utils"
utils.after_ui_enter(function()
  utils.mini_setup "pairs"
  utils.mini_setup("surround", {
    mappings = {
      add = "ys", -- Add surrounding in Normal and Visual modes
      delete = "dy", -- Delete surrounding
      replace = "cy", -- Replace surrounding
      find = "", -- Find surrounding (to the right)
      find_left = "", -- Find surrounding (to the left)
      highlight = "", -- Highlight surrounding
      update_n_lines = "", -- Update `n_lines`
      suffix_last = "", -- Suffix to search with "prev" method
      suffix_next = "", -- Suffix to search with "next" method
    },
  })

  utils.packadd "friendly-snippets" -- https://github.com/rafamadriz/friendly-snippets
  utils.packadd "blink.cmp" -- https://github.com/Saghen/blink.cmp
  require("blink.cmp").setup {
    keymap = {
      ---@diagnostic disable-next-line: assign-type-mismatch
      preset = "super-tab",
      ["<C-j>"] = { "select_next", "fallback" },
      ["<C-k>"] = { "select_prev", "fallback" },
      ["<C-l>"] = { "select_and_accept" },
    },
    completion = {
      documentation = { auto_show = true, window = { border = "double" } },
      menu = { border = "rounded" },
    },
    fuzzy = { prebuilt_binaries = { download = false } },
    signature = { enabled = true },
  }
end)

local nxo = { "n", "x", "o" }

---@type lz.n.Spec
return {
  {
    "leap.nvim", -- https://github.com/ggandor/leap.nvim
    after = function()
      require("leap").add_default_mappings(true)
      vim.api.nvim_set_hl(0, "LeapBackdrop", { link = "Comment" })
      vim.keymap.del({ "x", "o" }, "x")
      vim.keymap.del({ "x", "o" }, "X")
    end,
    keys = {
      { "s", mode = nxo, desc = "Leap forward to" },
      { "S", mode = nxo, desc = "Leap backward to" },
      { "gs", mode = nxo, desc = "Leap from windows" },
    },
  },
  {
    "flit.nvim", -- https://github.com/ggandor/flit.nvim
    before = function() require("lz.n").trigger_load "leap.nvim" end,
    after = function() require("flit").setup { labeled_modes = "nxo" } end,
    keys = {
      { "f", mode = nxo },
      { "F", mode = nxo },
      { "t", mode = nxo },
      { "T", mode = nxo },
    },
  },
  {
    "vim-illuminate", -- https://github.com/RRethy/vim-illuminate
    event = "BufReadPost",
  },
  {
    "spaceless.nvim", --  https://github.com/lewis6991/spaceless.nvim
    event = "BufReadPost",
  },

  {
    "vim-repeat", -- https://github.com/tpope/vim-repeat
    event = "DeferredUIEnter",
  },

  {
    "vim-crystal", -- https://github.com/vim-crystal/vim-crystal
    ft = "crystal",
  },
}
