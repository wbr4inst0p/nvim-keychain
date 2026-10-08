local config_mod = require("keychain.config")
local macos = require("keychain.macos")
local commands = require("keychain.commands")
local diagnostics = require("keychain.diagnostics")

local M = {}

M._config = nil

---@param opts table|nil
function M.setup(opts)
  if not macos.is_supported() then
    vim.notify(
      "keychain.nvim: the macOS `security` CLI was not found; commands will be unavailable on this system.",
      vim.log.levels.WARN
    )
  end

  local config = config_mod.build(opts)
  M._config = config

  commands.setup(config)
  diagnostics.setup(config)
end

---@return KeychainConfig
function M.get_config()
  return M._config or config_mod.build()
end

return M
