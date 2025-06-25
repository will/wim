vim.opt_local.spell = true

function _G.jj_foldexpr()
  local lnum = vim.v.lnum
  local line = vim.fn.getline(lnum)

  -- Blank lines reset folding to 0
  if line:match "^%s*$" then return 0 end

  -- If this is a section header, start a new fold at level 1
  if line:match "^JJ: [A-Z]" then
    if line:match "Change summary" then return 0 end
    return 1
  end

  if line:match "^JJ:      [ADM]" then return 0 end

  if line:match "^JJ:      diff" then return ">1" end

  return 1
end

vim.opt_local.foldmethod = "expr"
vim.opt_local.foldexpr = "v:lua.jj_foldexpr()"
vim.opt_local.foldenable = true
vim.opt_local.foldlevel = 0
