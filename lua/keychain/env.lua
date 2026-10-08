-- Pure(ish) .env parsing and rendering logic: no direct keychain/IO calls, so
-- it can be unit tested in isolation. Secret resolution is done via an
-- injected getter function (see resolve_entries).
local M = {}

M.REF_PREFIX = "keychain://"

---@class KeychainEnvEntry
---@field lnum number 1-based line number
---@field raw string original line, unmodified
---@field kind '"kv"'|'"comment"'|'"blank"'
---@field export boolean whether the line had a leading `export `
---@field key string|nil
---@field value string|nil the value, unquoted
---@field quote string|nil the quote char used ('"', "'"), or nil if unquoted
---@field ref_account string|nil set when value is a keychain://ACCOUNT reference

---Strip a single layer of matching surrounding quotes.
---@param value string
---@return string unquoted
---@return string|nil quote_char
local function strip_quotes(value)
  local quote = value:sub(1, 1)
  if (quote == '"' or quote == "'") and value:sub(-1) == quote and #value >= 2 then
    return value:sub(2, -2), quote
  end
  return value, nil
end

---@param value string
---@param quote string|nil
---@return string
local function apply_quotes(value, quote)
  if quote then
    return quote .. value .. quote
  end
  return value
end

---@param value string
---@return string|nil account
function M.parse_ref(value)
  if value:sub(1, #M.REF_PREFIX) == M.REF_PREFIX then
    local account = value:sub(#M.REF_PREFIX + 1)
    if account ~= "" then
      return account
    end
  end
  return nil
end

---@param account string
---@return string
function M.make_ref(account)
  return M.REF_PREFIX .. account
end

---Parse a single .env line.
---@param line string
---@param lnum number
---@return KeychainEnvEntry
function M.parse_line(line, lnum)
  local trimmed = vim.trim(line)

  if trimmed == "" then
    return { lnum = lnum, raw = line, kind = "blank" }
  end
  if trimmed:sub(1, 1) == "#" then
    return { lnum = lnum, raw = line, kind = "comment" }
  end

  local rest = trimmed
  local export = false
  local without_export = rest:match("^export%s+(.*)$")
  if without_export then
    rest = without_export
    export = true
  end

  local key, raw_value = rest:match("^([%w_][%w_%d]*)%s*=%s*(.*)$")
  if not key then
    return { lnum = lnum, raw = line, kind = "comment" }
  end

  local value, quote = strip_quotes(raw_value)
  local ref_account = quote == nil and M.parse_ref(value) or nil

  return {
    lnum = lnum,
    raw = line,
    kind = "kv",
    export = export,
    key = key,
    value = value,
    quote = quote,
    ref_account = ref_account,
  }
end

---@param lines string[]
---@return KeychainEnvEntry[]
function M.parse_lines(lines)
  local entries = {}
  for i, line in ipairs(lines) do
    entries[i] = M.parse_line(line, i)
  end
  return entries
end

---Render a `kv` entry back into a line, preserving export/quote style.
---@param entry KeychainEnvEntry
---@return string
function M.render_entry(entry)
  assert(entry.kind == "kv", "render_entry expects a kv entry")
  local prefix = entry.export and "export " or ""
  return string.format("%s%s=%s", prefix, entry.key, apply_quotes(entry.value, entry.quote))
end

---Build a `KEY=keychain://ACCOUNT` line, preserving export style from an
---optional existing entry.
---@param key string
---@param account string
---@param opts {export: boolean|nil}|nil
---@return string
function M.render_ref_line(key, account, opts)
  opts = opts or {}
  local prefix = opts.export and "export " or ""
  return string.format("%s%s=%s", prefix, key, M.make_ref(account))
end

---Resolve every `kv` entry into its final value: refs are resolved via
---`get_secret(account)`, plain values pass through unchanged.
---@param entries KeychainEnvEntry[]
---@param get_secret fun(account: string): boolean, string
---@return string[] lines
---@return table<string, string> errors keyed by account name
function M.resolve_entries(entries, get_secret)
  local lines = {}
  local errors = {}

  for _, entry in ipairs(entries) do
    if entry.kind ~= "kv" then
      lines[#lines + 1] = entry.raw
    elseif entry.ref_account then
      local ok, value_or_err = get_secret(entry.ref_account)
      if ok then
        lines[#lines + 1] = M.render_entry(vim.tbl_extend("force", entry, { value = value_or_err, quote = nil }))
      else
        errors[entry.ref_account] = value_or_err
        lines[#lines + 1] = string.format("# keychain.nvim: FAILED to resolve %s (%s)", entry.key, value_or_err)
      end
    else
      lines[#lines + 1] = entry.raw
    end
  end

  return lines, errors
end

---Resolve every `kv` entry into a plain key/value pair rather than a
---rendered line. Used when secrets need to end up somewhere other than a
---file - e.g. loaded directly into `vim.env` for the current Neovim
---session (see `:KeychainLoad`) instead of written to disk.
---@param entries KeychainEnvEntry[]
---@param get_secret fun(account: string): boolean, string
---@return {key: string, value: string}[] resolved
---@return table<string, string> errors keyed by account name
function M.resolve_values(entries, get_secret)
  local resolved = {}
  local errors = {}

  for _, entry in ipairs(entries) do
    if entry.kind == "kv" then
      if entry.ref_account then
        local ok, value_or_err = get_secret(entry.ref_account)
        if ok then
          resolved[#resolved + 1] = { key = entry.key, value = value_or_err }
        else
          errors[entry.ref_account] = value_or_err
        end
      else
        resolved[#resolved + 1] = { key = entry.key, value = entry.value }
      end
    end
  end

  return resolved, errors
end

local GENERATED_MARKER = "# Generated by keychain.nvim - do not edit, run :KeychainSync to regenerate"

---@return string
function M.generated_marker()
  return GENERATED_MARKER
end

---@param lines string[]
---@return boolean
function M.has_generated_marker(lines)
  return lines[1] == GENERATED_MARKER
end

---@param relpath string
---@return string
local function escape_gitignore_pattern(relpath)
  return relpath:gsub("([%.%-])", "\\%1")
end

---@param gitignore_lines string[]
---@param relpath string
---@return boolean
function M.is_gitignored(gitignore_lines, relpath)
  local pattern = "^" .. escape_gitignore_pattern(relpath) .. "$"
  local bare_pattern = "^/?" .. escape_gitignore_pattern(relpath) .. "/?$"
  for _, line in ipairs(gitignore_lines) do
    local trimmed = vim.trim(line)
    if trimmed == relpath or trimmed == "/" .. relpath then
      return true
    end
    if trimmed:match(bare_pattern) or trimmed:match(pattern) then
      return true
    end
  end
  return false
end

---@param gitignore_lines string[]
---@param relpath string
---@return string[] new_lines
function M.add_to_gitignore(gitignore_lines, relpath)
  local new_lines = vim.deepcopy(gitignore_lines)
  if #new_lines > 0 and new_lines[#new_lines] ~= "" then
    new_lines[#new_lines + 1] = ""
  end
  new_lines[#new_lines + 1] = relpath
  return new_lines
end

return M
