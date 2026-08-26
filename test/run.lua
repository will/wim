-- Test runner for neovim config smoke tests
-- Usage: nvim --headless -c "luafile test/run.lua"

-- Get the directory of this script
local script_dir = debug.getinfo(1, "S").source:sub(2):match "(.*/)"
if not script_dir then script_dir = "test/" end

-- Load helpers and store globally so test files can access the same instance
_G._test_helpers = dofile(script_dir .. "helpers.lua")
local helpers = _G._test_helpers

-- helpers.test() re-arms this per test; this only covers loading the files
helpers.arm_watchdog "loading the test files"

-- Find all test_*.lua files
local test_files = vim.fn.glob(script_dir .. "test_*.lua", false, true)
table.sort(test_files)

if #test_files == 0 then
  print("No test files found in " .. script_dir)
  vim.cmd "cq 1"
end

print("Running " .. #test_files .. " test file(s)...\n")

-- Run each test file
for _, file in ipairs(test_files) do
  local name = file:match "([^/]+)$"
  print("▶ " .. name)

  local ok, err = pcall(dofile, file)
  if not ok then
    helpers.failed = helpers.failed + 1
    table.insert(helpers.errors, name .. " (load error): " .. tostring(err))
    print("  ✗ Failed to load: " .. tostring(err))
  end

  print ""
end

-- Report and exit
helpers.report_and_exit()
