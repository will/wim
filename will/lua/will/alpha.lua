local packadd = require("will.utils").packadd

packadd "plenary.nvim"
packadd "nvim-web-devicons"
packadd "alpha-nvim"

vim.cmd [[
  augroup _alpha
    autocmd!
    autocmd User AlphaReady set showtabline=0 | autocmd BufUnload <buffer> set showtabline=2
  augroup end
]]

local alpha = require "alpha"

local i = 2
local dir = 1
local start = { tonumber("19", 16), tonumber("17", 16), tonumber("24", 16) }
local finish = { tonumber("FF", 16), 0, tonumber("7C", 16) }
local steps = 100
local delta = { (finish[1] - start[1]) / steps, (finish[2] - start[2]) / steps, (finish[3] - start[3]) / steps }
local hex = function(idx) return string.format("%02x", start[idx] + (delta[idx] * i)) end
local stop = false
local alpha_animate
alpha_animate = function()
  local sleep = 10
  local color = "#" .. hex(1) .. hex(2) .. hex(3)
  if (i == steps) or (i == 1) then
    sleep = 750 + (250 * dir)
    dir = dir * -1
  end
  i = i + dir
  vim.api.nvim_command("highlight AlphaHeader guifg=" .. color)
  if not stop then vim.defer_fn(alpha_animate, sleep) end
end
vim.api.nvim_create_autocmd("User", {
  pattern = "AlphaReady",
  callback = function()
    stop = false
    alpha_animate()
    vim.api.nvim_create_autocmd("User", {
      pattern = "AlphaClosed",
      callback = function() stop = true end,
      once = true,
    })
  end,
})

local dashboard = require "alpha.themes.dashboard"
--  dashboard.section.header.val = {
--    " ███╗   ██╗ ███████╗ ██████╗  ██╗   ██╗ ██╗ ███╗   ███╗",
--    " ████╗  ██║ ██╔════╝██╔═══██╗ ██║   ██║ ██║ ████╗ ████║",
--    " ██╔██╗ ██║ █████╗  ██║   ██║ ██║   ██║ ██║ ██╔████╔██║",
--    " ██║╚██╗██║ ██╔══╝  ██║   ██║ ╚██╗ ██╔╝ ██║ ██║╚██╔╝██║",
--    " ██║ ╚████║ ███████╗╚██████╔╝  ╚████╔╝  ██║ ██║ ╚═╝ ██║",
--    " ╚═╝  ╚═══╝ ╚══════╝ ╚═════╝    ╚═══╝   ╚═╝ ╚═╝     ╚═╝",
--  }

dashboard.section.header.val = {
  [[                                                                       ]],
  [[                                                                       ]],
  [[                                                                       ]],
  [[                                                                       ]],
  [[                                                                     ]],
  [[       ████ ██████           █████      ██                     ]],
  [[      ███████████             █████                             ]],
  [[      █████████ ███████████████████ ███   ███████████   ]],
  [[     █████████  ███    █████████████ █████ ██████████████   ]],
  [[    █████████ ██████████ █████████ █████ █████ ████ █████   ]],
  [[  ███████████ ███    ███ █████████ █████ █████ ████ █████  ]],
  [[ ██████  █████████████████████ ████ █████ █████ ████ ██████ ]],
  [[                                                                       ]],
  [[                                                                       ]],
  [[                                                                       ]],
}

dashboard.section.buttons.val = {
  dashboard.button("f", "󰈞  Find file", ":Telescope find_files <CR>"),
  dashboard.button("e", "  New file", ":ene <BAR> startinsert <CR>"),
  dashboard.button("l", "󰕍  Open last position", ":normal '0 <CR>"),
  dashboard.button("p", "  Find project", ":Telescope projects <CR>"),
  dashboard.button("r", "󰄉  Recently used files", ":Telescope oldfiles <CR>"),
  dashboard.button("t", "󰊄  Find text", ":Telescope live_grep <CR>"),
  dashboard.button("q", "󰅚  Quit Neovim", ":qa<CR>"),
}

local Job = require "plenary.job"
local footer = function()
  local j = Job:new { command = "oblique" } ---@diagnostic disable-line: missing-fields
  j:sync()
  return j:result()[1]
end

dashboard.section.footer.val = footer

dashboard.section.footer.opts.hl = "Type"
dashboard.section.header.opts.hl = "AlphaHeader"
dashboard.section.buttons.opts.hl = "Keyword"

dashboard.opts.opts.noautocmd = true
alpha.setup(dashboard.opts)
