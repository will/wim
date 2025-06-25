vim.opt_local.spell = true

local exists = function(path) return vim.uv.fs_stat(path) and path or nil end
local root_dir = vim.fs.root(0, { "Gemfile", ".git" })

if exists "Gemfile.lock" then
  vim.lsp.start {
    name = "ruby-lsp",
    cmd = { "ruby-lsp" },
    root_dir = root_dir,
    init_options = {
      formatter = "standard",
      linters = { "standard" },
      indexing = {
        -- stylua: ignore start
        excludedGems = {
          "aws-eventstream", "aws-partitions", "aws-sdk-cloudwatch", "aws-sdk-cloudwatchlogs", "aws-sdk-core",
          "aws-sdk-ec2", "aws-sdk-elasticloadbalancingv2", "aws-sdk-kms", "aws-sdk-route53", "aws-sdk-s3", "aws-sdk-iam",
          "aws-sigv4", "bundler", "digest-crc", "google-apis-compute_v1", "google-apis-core", "google-apis-dns_v1",
          "google-apis-iam_v1", "google-apis-iamcredentials_v1", "google-apis-storage_v1", "google-cloud-core",
          "google-cloud-env", "google-cloud-errors", "google-cloud-storage", "language_server-protocol", "opentelemetry-api",
          "opentelemetry-common", "opentelemetry-helpers-sql-obfuscation", "opentelemetry-instrumentation-aws_sdk",
          "opentelemetry-instrumentation-base", "opentelemetry-instrumentation-excon", "opentelemetry-instrumentation-faraday",
          "opentelemetry-instrumentation-pg", "opentelemetry-instrumentation-rack", "opentelemetry-registry", "opentelemetry-sdk",
          "opentelemetry-semantic_conventions", "parser", "prism", "rbs", "rdoc", "rubocop", "sorbet-static", "yard",
        },
        -- stylua: ignore end
      },
    },
    capabilities = { general = { positionEncodings = { "utf-16" } } },
  }
end

if exists "sorbet/config" then
  vim.lsp.start {
    name = "sorbet",
    cmd = { "srb", "tc", "--lsp", "--enable-all-beta-lsp-features" },
    root_dir = root_dir,
  }
end

vim.fn.sign_define("NocovSign", { text = "", texthl = "WarningMsg", linehl = "", numhl = "" })
vim.fn.sign_define("NocovSignBetween", { text = "┃", texthl = "WarningMsg", linehl = "", numhl = "" })
vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "InsertLeave" }, {
  callback = function()
    local api = vim.api
    local bufnr = api.nvim_get_current_buf()

    local query = vim.treesitter.query.parse("ruby", [[ ((comment) @c (#eq? @c "# :nocov:")) ]])
    vim.fn.sign_unplace("NocovGroup", { buffer = bufnr })

    local parser = vim.treesitter.get_parser(bufnr, "ruby")
    local tree = parser:parse()[1]
    local root = tree:root()
    local ranges = {}
    for _, matches, _ in query:iter_matches(root, bufnr, 0, -1, { all = true }) do
      for _, nodes in pairs(matches) do
        -- local capture_name = query.captures[id]
        -- if capture_name == "c"
        for _, node in ipairs(nodes) do
          local start_row, _, _, _ = node:range()
          table.insert(ranges, start_row + 1)
          vim.fn.sign_place(0, "NocovGroup", "NocovSign", bufnr, { lnum = start_row + 1 })
        end
      end
    end
    for i = 1, #ranges, 2 do
      if not ranges[i + 1] then break end
      for j = ranges[i] + 1, ranges[i + 1] do
        vim.fn.sign_place(0, "NocovGroup", "NocovSignBetween", bufnr, { lnum = j, priority = 7 })
      end
    end
  end,
})
