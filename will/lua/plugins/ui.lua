local utils = require "will.utils"

vim.api.nvim_create_autocmd("BufReadPre", {
  callback = function()
    -- Indent marker
    -- before lukas-reineke/indent-blankline.nvim
    utils.mini_setup "indentscope"
  end,
})

vim.api.nvim_create_autocmd({ "BufAdd", "BufEnter" }, {
  callback = function()
    -- tab/buffer line
    -- before akinsho/nvim-bufferline.lua
    --  maybe was nicer, had unsaved marker
    utils.mini_setup "icons" -- call before tabline setup
  end,
})

---@type lz.n.Spec
return {
  {
    "bufferline.nvim", -- https://github.com/akinsho/bufferline.nvim
    event = { "BufAdd", "BufEnter" },
    after = function()
      require("bufferline").setup {
        options = {
          buffer_close_icon = "",
          diagnostics = "nvim_lsp",
          offsets = {
            { filetype = "neo-tree", text = "NeoTree", highlight = "Directory", text_align = "left", padding = 1 },
          },
        },
      }
    end,
  },

  {
    "noice.nvim", -- https://github.com/folke/noice.nvim
    event = "DeferredUIEnter",
    before = function()
      utils.packadd "nui.nvim"
      utils.packadd "nvim-notify"
      require("notify").setup { ---@diagnostic disable-line: missing-fields
        background_colour = "#000000",
      }
      utils.keymap("n", "<esc>", "<esc><cmd>lua require('notify').dismiss()<cr>", "Dismiss noftifications")
    end,
    after = function()
      require("noice").setup {
        lsp = {
          -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
          override = {
            ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
            ["vim.lsp.util.stylize_markdown"] = true,
          },
        },
        -- you can enable a preset for easier configuration
        presets = {
          bottom_search = true, -- use a classic bottom cmdline for search
          command_palette = true, -- position the cmdline and popupmenu together
          long_message_to_split = true, -- long messages will be sent to a split
          inc_rename = false, -- enables an input dialog for inc-rename.nvim
          lsp_doc_border = true, -- add a border to hover docs and signature help
        },
        routes = {
          {
            filter = {
              event = "msg_show",
              any = {
                { find = "%d+L, %d+B" },
                { find = "; after #%d+" },
                { find = "; before #%d+" },
              },
            },
            view = "mini",
          },
          {
            filter = {
              warning = true,
              event = "notify",
              cond = function(e) return vim.startswith(e:content(), "position_encoding param is required") end,
            },
            opts = { skip = true },
          },
        },
      }

      utils.keymap("c", "<S-Enter>", function() require("noice").redirect(vim.fn.getcmdline()) end, "Redirect Cmdline")

      vim.keymap.set({ "n", "i", "s" }, "<c-f>", function()
        if not require("noice.lsp").scroll(4) then return "<c-f>" end
      end, { silent = true, expr = true })

      vim.keymap.set({ "n", "i", "s" }, "<c-b>", function()
        if not require("noice.lsp").scroll(-4) then return "<c-b>" end
      end, { silent = true, expr = true })
    end,
  },
}
