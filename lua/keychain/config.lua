local M = {}

---@class KeychainDetectionConfig
---@field enabled boolean
---@field min_entropy number Minimum Shannon entropy (bits/char) to flag a value on its own.
---@field min_length number Minimum value length considered for the entropy check.
---@field key_patterns string[] Lua patterns (case-insensitive) matched against the env key name.
---@field ignore_values string[] Lua patterns (case-insensitive) for placeholder values to ignore.

---@class KeychainSyncConfig
---@field target string Default output path (relative to the source .env) for `:KeychainSync`.
---@field add_marker boolean Whether to prepend a "generated" marker comment to the synced file.
---@field auto_gitignore boolean Whether to offer appending the target to .gitignore.

---@class KeychainConfig
---@field service_prefix string
---@field project_id_strategy '"git_root"'|'"cwd"'
---@field env_file_patterns string[] Lua patterns matched against the buffer's file name (tail).
---@field env_file_ignore_patterns string[] Lua patterns for files to never treat as .env files.
---@field sync KeychainSyncConfig
---@field detection KeychainDetectionConfig
---@field reveal_seconds number How long a revealed secret stays visible / in the scratch register.
---@field scratch_register string Register used by `:KeychainGet` to hold the revealed secret.

---@type KeychainConfig
M.defaults = {
  service_prefix = "nvim-env:",
  project_id_strategy = "git_root",

  -- Matched against the tail (file name) of the buffer path.
  env_file_patterns = {
    "^%.env$",
    "^%.env%.[%w_.-]+$",
  },
  env_file_ignore_patterns = {
    "%.example$",
    "%.sample$",
    "%.template$",
  },

  sync = {
    target = ".env.local",
    add_marker = true,
    auto_gitignore = true,
  },

  detection = {
    enabled = true,
    -- Threshold applied when the key name itself looks secret-ish.
    min_entropy = 3.0,
    min_length = 8,
    -- Stricter thresholds applied when the key name does NOT match any
    -- pattern above, to catch secrets under generic names while limiting
    -- false positives (hashes, base64 blobs, etc.).
    min_entropy_unnamed = 3.6,
    min_length_unnamed = 20,
    key_patterns = {
      "SECRET",
      "TOKEN",
      "PASSWORD",
      "PASSWD",
      "PRIVATE[_-]?KEY",
      "API[_-]?KEY",
      "ACCESS[_-]?KEY",
      "CLIENT[_-]?SECRET",
      "CREDENTIAL",
      "AUTH",
      "SESSION[_-]?KEY",
      "SIGNING[_-]?KEY",
    },
    ignore_values = {
      "^changeme$",
      "^change_me$",
      "^xxx+$",
      "^todo$",
      "^tbd$",
      "^n/?a$",
      "^none$",
      "^null$",
      "^example$",
      "^your.-here$",
      "^your.-key$",
      "^<.*>$",
      "^%${.*}$",
      "^%[.*%]$",
      "^%.%.%.$",
    },
  },

  reveal_seconds = 10,
  scratch_register = "z",
}

---Merge user options on top of the defaults.
---@param opts table|nil
---@return KeychainConfig
function M.build(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
