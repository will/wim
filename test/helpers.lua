-- Test helpers for neovim config smoke tests
-- When run via run.lua, use global state; otherwise create local state
local M = _G._test_helpers or {
  errors = {},
  passed = 0,
  failed = 0,
  skipped = 0,
}

local boot = dofile((debug.getinfo(1, "S").source:sub(2):match "(.*/)" or "test/") .. "boot.lua")

--- Case-insensitive substring, set from ntest --filter. A filtered run is a debugging
--- aid, not a verdict: tests here drive plugins that later tests observe, so a subset can
--- pass in isolation and fail together, or the reverse.
M.filter = M.filter or vim.env.WIM_TEST_FILTER
M.skipped = M.skipped or 0

-- Watchdog against nvim sitting on a prompt forever. Armed per test rather than once
-- for the run: tests legitimately wait tens of seconds for real work (a diff view
-- fetching history, leap's scheduled visit hops), and because vim.wait pumps the loop a
-- whole-run deadline fires mid-wait and kills the run with `cq 124` instead of failing
-- something diagnosable.
local WATCHDOG_SECONDS = 120
M._watchdog = M._watchdog or vim.uv.new_timer()

---@param label string What the watchdog will blame if it fires
function M.arm_watchdog(label)
  M._watchdog:stop()
  M._watchdog:start(
    WATCHDOG_SECONDS * 1000,
    0,
    vim.schedule_wrap(function()
      print(string.format("\n\nTIMEOUT: %s took longer than %d seconds", label, WATCHDOG_SECONDS))
      print "This usually means neovim is waiting for input."
      vim.cmd "cq 124"
    end)
  )
end

--- Run a test case
---@param name string Test name
---@param fn function Test function (should error on failure)
function M.test(name, fn)
  if M.filter and M.filter ~= "" and not name:lower():find(M.filter:lower(), 1, true) then
    M.skipped = M.skipped + 1
    return
  end

  M.arm_watchdog(name)

  local ok, err = boot.strict_pcall(fn)

  if ok then
    M.passed = M.passed + 1
    print("  ✓ " .. name)
  else
    M.failed = M.failed + 1
    table.insert(M.errors, name .. ": " .. tostring(err))
    print("  ✗ " .. name .. ": " .. tostring(err))
  end
end

--- Assert that a module can be required
---@param mod string Module name
function M.require_ok(mod)
  local ok, err = pcall(require, mod)
  if not ok then error("failed to require '" .. mod .. "': " .. tostring(err)) end
end

--- Assert condition is truthy
---@param cond any Condition to check
---@param msg string? Optional error message
function M.assert(cond, msg)
  if not cond then error(msg or "assertion failed") end
end

--- Assert two values are equal
---@param expected any Expected value
---@param actual any Actual value
---@param msg string? Optional error message
function M.eq(expected, actual, msg)
  if expected ~= actual then
    error((msg or "values not equal") .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
  end
end

--- Drain scheduled work, and bring plugins or a file up to the state an interactive
--- session would have. Shared with nprobe and ndump, so a tool and a test cannot
--- disagree about what "loaded" means. See test/boot.lua.
M.settle = boot.settle
M.deferred = boot.deferred
M.load = boot.load
M.open = boot.open

--- Teardown for anything that opened a telescope picker: the picker schedules its own
--- `startinsert`, which outlives the window and would otherwise eat the first keys the
--- next test feeds.
function M.leave_picker()
  M.settle()
  vim.api.nvim_feedkeys("", "x", false)
  vim.cmd "stopinsert"
end

--- Print summary and exit with appropriate code
function M.report_and_exit()
  M._watchdog:stop()
  print(string.format("\n%d passed, %d failed", M.passed, M.failed))
  if M.skipped > 0 then print(string.format("%d skipped by --filter %s", M.skipped, M.filter)) end

  -- a filter that matches nothing would otherwise report a clean run of no tests
  if M.filter and M.passed + M.failed == 0 then
    print("\nno test matched --filter " .. M.filter)
    vim.cmd "cq 2"
  end

  if M.failed > 0 then
    print "\nFailed tests:"
    for _, e in ipairs(M.errors) do
      print("  " .. e)
    end
    vim.cmd "cq 1"
  end

  -- qa!, not q: plugins like neo-tree re-open their window off a timer, so the last
  -- window is not necessarily the only one, and a stray modified buffer would sit on an
  -- E37 prompt until the watchdog fired.
  vim.cmd "qa!"
end

--- Reset state (useful when running multiple test files)
function M.reset()
  M.errors = {}
  M.passed = 0
  M.failed = 0
  M.skipped = 0
end

return M
