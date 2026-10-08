-- Heuristics for spotting plaintext secrets in .env-style key/value entries.
-- Pure logic, no vim.diagnostic/UI calls here, so it stays easy to unit test.
local M = {}

---Shannon entropy in bits per character.
---@param value string
---@return number
function M.shannon_entropy(value)
  if #value == 0 then
    return 0
  end

  local counts = {}
  for i = 1, #value do
    local c = value:sub(i, i)
    counts[c] = (counts[c] or 0) + 1
  end

  local len = #value
  local entropy = 0
  for _, count in pairs(counts) do
    local p = count / len
    entropy = entropy - (p * (math.log(p) / math.log(2)))
  end
  return entropy
end

---@param key string
---@param patterns string[]
---@return boolean
function M.key_matches(key, patterns)
  local upper = key:upper()
  for _, pattern in ipairs(patterns) do
    if upper:find(pattern) then
      return true
    end
  end
  return false
end

---@param value string
---@param patterns string[]
---@return boolean
function M.is_placeholder(value, patterns)
  local lower = value:lower()
  for _, pattern in ipairs(patterns) do
    if lower:match(pattern) then
      return true
    end
  end
  return false
end

---Decide whether an env entry looks like a plaintext secret.
---@param entry KeychainEnvEntry
---@param config KeychainConfig
---@return boolean flagged
---@return string|nil reason
function M.is_plaintext_secret(entry, config)
  local d = config.detection
  if not d.enabled then
    return false
  end
  if entry.kind ~= "kv" or entry.ref_account or not entry.value or entry.value == "" then
    return false
  end
  if M.is_placeholder(entry.value, d.ignore_values) then
    return false
  end

  local key_match = M.key_matches(entry.key, d.key_patterns)
  local entropy = M.shannon_entropy(entry.value)
  local length = #entry.value

  if key_match and (length >= d.min_length or entropy >= d.min_entropy) then
    return true,
      string.format(
        "'%s' looks like a secret key with a plaintext value (len=%d, entropy=%.1f). Run :KeychainSet or :KeychainMigrate.",
        entry.key,
        length,
        entropy
      )
  end

  if not key_match and length >= d.min_length_unnamed and entropy >= d.min_entropy_unnamed then
    return true,
      string.format(
        "'%s' has a high-entropy plaintext value (len=%d, entropy=%.1f) that may be a secret. Run :KeychainSet or :KeychainMigrate.",
        entry.key,
        length,
        entropy
      )
  end

  return false
end

---Scan a full set of parsed entries.
---@param entries KeychainEnvEntry[]
---@param config KeychainConfig
---@return {entry: KeychainEnvEntry, reason: string}[]
function M.scan(entries, config)
  local flagged = {}
  for _, entry in ipairs(entries) do
    local is_secret, reason = M.is_plaintext_secret(entry, config)
    if is_secret then
      flagged[#flagged + 1] = { entry = entry, reason = reason }
    end
  end
  return flagged
end

return M
