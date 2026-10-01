local o = vim.opt_local

o.conceallevel = 3
o.spell = true

o.textwidth = 119
o.colorcolumn = "120"

-- lz.n re-fires FileType once it has packadd'ed neorg, so this file can be sourced twice
-- for one buffer: the keymap below is `unique` and the autocommand would double up.
if not vim.b.will_norg_attached then
  vim.b.will_norg_attached = true
  require("will.journal").attach(0)
end
