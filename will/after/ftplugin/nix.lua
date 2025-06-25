vim.lsp.start {
  name = "nix",
  cmd = { "nixd" },
  root_dir = vim.fs.root(0, { "flake.nix", ".git" }),
}
