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
    -- nix builds the matcher, never fall back to (or fetch) anything else
    fuzzy = { implementation = "rust" },
    signature = { enabled = true },
  }
end)

local nxo = { "n", "x", "o" }
local xo = { "x", "o" }

---@type lz.n.Spec
return {
  {
    "leap.nvim", -- https://codeberg.org/ggandor/leap.nvim
    after = function()
      vim.keymap.set(nxo, "s", "<Plug>(leap-forward)")
      vim.keymap.set(nxo, "S", "<Plug>(leap-backward)")
      -- gs/gS belong to Visitor mode below, so cross-window leaping lives on gW
      vim.keymap.set(nxo, "gW", "<Plug>(leap-from-window)")
      require("leap.user").set_backdrop_highlight "Comment"

      -- Visitor mode: leap away, operate there, come back. Upstream's keys, see
      -- :h leap-visit
      vim.keymap.set(nxo, "gs", "<Plug>(leap-visit)")
      vim.keymap.set(nxo, "gS", "<Plug>(leap-visit-linewise)")
      vim.keymap.set(xo, "ar", "<Plug>(leap-visit-text-object)")
      vim.keymap.set(xo, "ir", "<Plug>(leap-visit-inner-text-object)")
      vim.keymap.set("o", "rr", "<Plug>(leap-visit-line)")

      -- Autopaste (:h leap-visit-autopaste): text yanked at the visited region comes
      -- back and is pasted where the visit started, so `yarp{leap}` clones a remote
      -- paragraph.
      --
      -- A visit that named no register reports '"'. Accepting '+' and '*' as well means
      -- an explicit "+yarw autopastes too, rather than looking like a deliberate choice
      -- to send the text somewhere else.
      local default_register = { ['"'] = true, ["+"] = true, ["*"] = true }

      vim.api.nvim_create_autocmd("User", {
        pattern = "VisitDone",
        group = vim.api.nvim_create_augroup("LeapVisitAutopaste", { clear = true }),
        callback = function(event)
          -- Visual mode visits yank the selection before leaping (see
          -- :h leap-visit-visual), so those always want the paste; every other
          -- mode only when the remote action itself was a yank, or a remote `d`
          -- would paste its own spoils back. An empty register would just be E353.
          local yanked = event.data.mode:match "^[vV\22]" or vim.v.operator == "y"
          if not yanked or not default_register[event.data.register] then return end
          if vim.fn.getreg '"' == "" then return end
          -- explicitly the register checked above: the visit may have named '+', and
          -- pasting that would go out to the clipboard provider for text nvim already has
          vim.cmd 'normal! ""p'
        end,
      })

      -- one-char f/t motions, replacing the unmaintained flit.nvim
      local function ft(args)
        require("leap").leap(vim.tbl_deep_extend("keep", args, {
          inputlen = 1,
          inclusive = true,
          opts = {
            labels = "", -- always autojump, safe labels for the rest
            vim_opts = { ["go.ignorecase"] = false }, -- f/t is case sensitive, like vanilla
          },
        }))
      end

      vim.keymap.set(nxo, "f", function() ft {} end, { desc = "Leap to char" })
      vim.keymap.set(nxo, "F", function() ft { backward = true } end, { desc = "Leap back to char" })
      vim.keymap.set(nxo, "t", function() ft { offset = -1 } end, { desc = "Leap till char" })
      vim.keymap.set(nxo, "T", function() ft { backward = true, offset = 1 } end, { desc = "Leap back till char" })
    end,
    keys = {
      { "s", mode = nxo, desc = "Leap forward to" },
      { "S", mode = nxo, desc = "Leap backward to" },
      { "gW", mode = nxo, desc = "Leap from window" },
      { "gs", mode = nxo, desc = "Leap visit" },
      { "gS", mode = nxo, desc = "Leap visit linewise" },
      { "ar", mode = xo, desc = "Leap visit a text object" },
      { "ir", mode = xo, desc = "Leap visit inner text object" },
      { "rr", mode = "o", desc = "Leap visit line" },
      { "f", mode = nxo, desc = "Leap to char" },
      { "F", mode = nxo, desc = "Leap back to char" },
      { "t", mode = nxo, desc = "Leap till char" },
      { "T", mode = nxo, desc = "Leap back till char" },
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
