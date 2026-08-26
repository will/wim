-- The harness behind `nprobe`: boot the real config headlessly, run one expression or
-- file inside it, print whatever came back, and exit nonzero if anything went wrong.
--
-- Written for the one-off questions that used to mean a throwaway script under /tmp,
-- which each had to rediscover the same two things: nothing lazy is loaded in a headless
-- session, and an error thrown from a scheduled callback prints a traceback and still
-- exits 0.
--
-- nprobe hands its options over in the environment rather than in nvim's argv, so a
-- payload sees the argv it would have had on its own.
local here = debug.getinfo(1, "S").source:sub(2):match "(.*/)" or "test/"
local boot = dofile(here .. "boot.lua")

local function fail(msg)
  io.stderr:write("nprobe: " .. msg .. "\n")
  vim.cmd "cq 1"
end

local function env(name)
  local value = vim.env[name]
  return value ~= nil and value ~= "" and value or nil
end

boot.deferred()

local open = env "WIM_PROBE_OPEN"
if open then
  local ok, err = pcall(boot.open, open)
  if not ok then fail("could not open " .. open .. ": " .. tostring(err)) end
end

local names = env "WIM_PROBE_LOAD_ALL" and boot.plugin_names()
  or vim.split(env "WIM_PROBE_LOAD" or "", ",", { trimempty = true })
local failures = boot.load(names)
if #failures > 0 then fail("could not load " .. table.concat(failures, "; ")) end

local chunk, err
local expr = env "WIM_PROBE_EXPR"
if expr then
  -- an expression or a statement, whichever parses, the way `:lua =` accepts both
  chunk, err = load("return " .. expr, "=(nprobe)")
  if not chunk then
    chunk, err = load(expr, "=(nprobe)")
  end
else
  local file = env "WIM_PROBE_FILE" or fail "nothing to run: pass a lua file or -e <expr>"
  chunk, err = loadfile(file)
end
if not chunk then fail("could not parse: " .. tostring(err)) end

-- luajit has no table.pack, and nil in the middle of a result list matters here
local function pack(...) return { n = select("#", ...), ... } end

local results
local ok, run_err = boot.strict_pcall(function() results = pack(chunk()) end, 2)
if not ok then fail(run_err or "failed") end

for i = 1, results.n do
  local value = results[i]
  print(type(value) == "string" and value or vim.inspect(value))
end

vim.cmd "qa!"
