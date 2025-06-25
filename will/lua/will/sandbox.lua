local realsandbox = loadfile(os.getenv "HOME" .. "/.config/wim/sandbox.lua")
if realsandbox then
  return realsandbox()
else
  local ensure_sandbox = os.getenv "ENSURE_NVIM_SANDBOX" == "true"
  return {
    sandboxed = function() return not ensure_sandbox end,
    start_sandbox = function()
      if ensure_sandbox then vim.print "asked to sandbox but real sandbox not found" end
    end,
  }
end
