-- Thin synchronous wrapper around the macOS `security` CLI for storing/retrieving
-- "generic password" keychain items. All calls go through vim.system with an
-- argv table (never a shell string), so values are never shell-interpolated.
local M = {}

---@return boolean
function M.is_supported()
  return vim.uv.os_uname().sysname == "Darwin" and vim.fn.executable("security") == 1
end

local function run(args)
  local ok, result = pcall(function()
    return vim.system(args, { text = true }):wait()
  end)
  if not ok then
    return false, tostring(result)
  end
  return true, result
end

---Store (or update) a secret in the login keychain.
---@param service string
---@param account string
---@param value string
---@return boolean ok
---@return string|nil err
function M.set(service, account, value)
  if not M.is_supported() then
    return false, "keychain.nvim: macOS Keychain is not available on this system"
  end

  local ok, result = run({
    "security",
    "add-generic-password",
    "-a", account,
    "-s", service,
    "-w", value,
    "-U", -- update the item in place if it already exists
  })
  if not ok then
    return false, result
  end
  if result.code ~= 0 then
    return false, vim.trim(result.stderr or ("security exited with code " .. result.code))
  end
  return true, nil
end

---Retrieve a secret from the login keychain.
---@param service string
---@param account string
---@return boolean ok
---@return string value_or_err The secret on success, an error message on failure.
function M.get(service, account)
  if not M.is_supported() then
    return false, "keychain.nvim: macOS Keychain is not available on this system"
  end

  local ok, result = run({
    "security",
    "find-generic-password",
    "-a", account,
    "-s", service,
    "-w",
  })
  if not ok then
    return false, result
  end
  if result.code ~= 0 then
    local err = vim.trim(result.stderr or "")
    if err == "" then
      err = ("no keychain entry found for account %q, service %q"):format(account, service)
    end
    return false, err
  end
  return true, (result.stdout:gsub("\n$", ""))
end

---@param service string
---@param account string
---@return boolean
function M.exists(service, account)
  local ok = M.get(service, account)
  return ok
end

---Delete a secret from the login keychain.
---@param service string
---@param account string
---@return boolean ok
---@return string|nil err
function M.delete(service, account)
  if not M.is_supported() then
    return false, "keychain.nvim: macOS Keychain is not available on this system"
  end

  local ok, result = run({
    "security",
    "delete-generic-password",
    "-a", account,
    "-s", service,
  })
  if not ok then
    return false, result
  end
  if result.code ~= 0 then
    return false, vim.trim(result.stderr or ("security exited with code " .. result.code))
  end
  return true, nil
end

return M
