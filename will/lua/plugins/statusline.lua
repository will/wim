local utils = require "will.utils"

---@type lz.n.Spec
return {
  "lualine.nvim",
  event = "DeferredUIEnter",
  before = utils.fpackadd "nvim-web-devicons",
  after = function()
    local hide_in_width = function() return vim.fn.winwidth(0) > 80 end

    local diagnostics = {
      "diagnostics",
      sources = { "nvim_diagnostic" },
      sections = { "error", "warn" },
      symbols = { error = " ", warn = " " },
      colored = false,
      update_in_insert = false,
      always_visible = true,
    }

    local diff = {
      "diff",
      colored = false,
      symbols = { added = " ", modified = " ", removed = " " }, -- changes diff symbols
      cond = hide_in_width,
    }

    local mode = { "mode", fmt = function(str) return "-- " .. str .. " --" end }
    local encoding = { "encoding", fmt = function(str) return str == "utf-8" and "" or str end }
    local filetype = { "filetype", icons_enabled = false, icon = nil }
    local branch = { "branch", icons_enabled = true, icon = "" }
    local location = { "location", padding = 0 }

    -- cool function for progress
    local progress = function()
      local current_line = vim.fn.line "."
      local total_lines = vim.fn.line "$"
      local chars = { "__", "▁▁", "▂▂", "▃▃", "▄▄", "▅▅", "▆▆", "▇▇", "██" }
      local line_ratio = current_line / total_lines
      local index = math.ceil(line_ratio * #chars)
      return chars[index]
    end

    local spaces = function()
      local count = vim.api.nvim_get_option_value("shiftwidth", { scope = "local" })
      return count == 2 and "" or "spaces: " .. count
    end

    local noice = function(thing)
      return {
        ---@diagnostic disable: undefined-field
        function() return require("noice").api.status[thing].get() end, ---@diagnostic disable-line
        cond = function() return package.loaded["noice"] and require("noice").api.status[thing].has() end,
        ---@diagnostic enable: undefined-field
      }
    end

    local noice_command = noice "command"
    local noice_search = noice "search"
    local noice_mode = noice "mode"

    require("lualine").setup {
      options = {
        globalstatus = true,
        icons_enabled = true,
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
        disabled_filetypes = { "alpha", "dashboard", "Outline" },
      },
      sections = {
        lualine_a = { branch, diagnostics },
        lualine_b = { mode },
        lualine_c = { noice_search },
        lualine_x = { noice_command, noice_mode, diff, spaces, encoding, filetype },
        lualine_y = { location },
        lualine_z = { progress },
      },
      inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = { "filename" },
        lualine_x = { "location" },
        lualine_y = {},
        lualine_z = {},
      },
      tabline = {},
      extensions = { "neo-tree", "toggleterm", "man", "nvim-dap-ui", "trouble" },
    }
  end,
}
