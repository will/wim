local lsp_configured = false
local function configure_lsp()
  if lsp_configured then return end

  -- Sign Column
  vim.opt.signcolumn = "yes"
  vim.diagnostic.config {
    float = { border = "rounded" },
    -- focusable = false,
    -- style = "minimal",
    -- source = "always",
    -- header = "",
    -- prefix = "",
    signs = {
      text = {
        [vim.diagnostic.severity.ERROR] = "✘", -- 
        [vim.diagnostic.severity.WARN] = "▲", -- 
        [vim.diagnostic.severity.HINT] = "⚑", -- 
        [vim.diagnostic.severity.INFO] = "»", -- 
      },
    },
    virtual_lines = { enable = true, current_line = true },
  }

  -- Popups rounded
  if not package.loaded["noice"] then
    vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "rounded" })
    vim.lsp.handlers["textDocument/signatureHelp"] =
      vim.lsp.with(vim.lsp.handlers.signature_help, { border = "rounded" })
  end

  -- Disable diagnostics while in insert mode
  vim.api.nvim_create_autocmd("ModeChanged", {
    pattern = { "n:i", "v:s" },
    desc = "Disable diagnostics in insert and select mode",
    callback = function(e) vim.diagnostic.enable(false, { bufnr = e.buf }) end,
  })
  vim.api.nvim_create_autocmd("ModeChanged", {
    pattern = "i:n",
    desc = "Enable diagnostics when leaving insert mode",
    callback = function(e) vim.diagnostic.enable(true, { bufnr = e.buf }) end,
  })

  lsp_configured = true
end

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(event)
    configure_lsp()

    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if not client then
      vim.notify "lsp attach but client missing"
      return
    end

    -- Format the current buffer on save
    if client.supports_method "textDocument/formatting" then
      vim.api.nvim_create_autocmd("BufWritePre", {
        buffer = event.buf,
        callback = function()
          vim.lsp.buf.format { bufnr = event.buf, id = client.id, async = false, timeout_ms = 10000 }
        end,
      })
    end

    local km = require("will.utils").keymap
    local bufmap = function(lhs, rhs, desc) km("n", lhs, rhs, desc, { buffer = event.buf, unique = false }) end

    -- bufmap("n", "gd", "<cmd>lua vim.lsp.buf.definition()<cr>", "Go to definition")
    -- bufmap("n", "gD", "<cmd>lua vim.lsp.buf.declaration()<cr>", "Go to declaration")
    -- bufmap("n", "go", "<cmd>lua vim.lsp.buf.type_definition()<cr>", "Go to type definition")
    -- bufmap("n", "gr", "<cmd>lua vim.lsp.buf.references()<cr>", "List references")
    -- bufmap("n", "gf", "<cmd>lua vim.lsp.buf.format()<cr>", "Format file")
    bufmap("gd", vim.lsp.buf.definition, "Go to definition")
    bufmap("gD", vim.lsp.buf.declaration, "Go to declaration")
    bufmap("go", vim.lsp.buf.type_definition, "Go to type definition")
    bufmap("gr", vim.lsp.buf.references, "List references")
    bufmap("gf", vim.lsp.buf.format, "Format file")
  end,
})
