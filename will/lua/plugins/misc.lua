---@type lz.n.Spec
return {
  {
    "vim-startuptime",
    cxmd = "StartupTime",
    before = function()
      vim.g.startuptime_tries = 50
      vim.g.startuptime_event_width = 0
    end,
  },
}
