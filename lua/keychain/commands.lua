local macos = require("keychain.macos")
local project = require("keychain.project")
local env = require("keychain.env")
local detect = require("keychain.detect")
local diagnostics = require("keychain.diagnostics")
local ui = require("keychain.ui")

local M = {}

-- Tracks keys set by :KeychainLoad in this Neovim session, so :KeychainUnload
-- knows what it's safe to clear.
local loaded_keys = {}

---@param bufnr integer
---@return KeychainEnvEntry[]
local function buffer_entries(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return env.parse_lines(lines)
end

---@param bufnr integer
---@return KeychainEnvEntry|nil
local function entry_under_cursor(bufnr)
  if bufnr ~= vim.api.nvim_get_current_buf() then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  if not line then
    return nil
  end
  return env.parse_line(line, lnum)
end

---Resolve the key/account to operate on from an optional CLI arg or the
---entry under the cursor.
---@param bufnr integer
---@param arg_key string|nil
---@return string|nil key
---@return KeychainEnvEntry|nil entry
local function resolve_key(bufnr, arg_key)
  if arg_key and arg_key ~= "" then
    return arg_key, nil
  end
  local entry = entry_under_cursor(bufnr)
  if entry and entry.kind == "kv" then
    return entry.ref_account or entry.key, entry
  end
  return nil, nil
end

local function rescan(bufnr, config)
  diagnostics.scan_buffer(bufnr, config)
end

---@param config KeychainConfig
function M.set(config, arg_key)
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local key, entry = resolve_key(bufnr, arg_key)

  local function proceed(k)
    if not k or k == "" then
      vim.notify("keychain.nvim: no key given", vim.log.levels.WARN)
      return
    end
    if not k:match("^[%w_][%w_%d]*$") then
      vim.notify("keychain.nvim: invalid key name '" .. k .. "'", vim.log.levels.ERROR)
      return
    end

    ui.input_secret({ prompt = "Value for " .. k }, function(value)
      if value == nil then
        vim.notify("keychain.nvim: cancelled", vim.log.levels.INFO)
        return
      end

      local service = project.service(config, path)
      local ok, err = macos.set(service, k, value)
      if not ok then
        vim.notify("keychain.nvim: failed to store secret: " .. err, vim.log.levels.ERROR)
        return
      end

      local export = entry and entry.export or false
      local new_line = env.render_ref_line(k, k, { export = export })

      local target_lnum = nil
      if entry and entry.kind == "kv" and entry.key == k then
        target_lnum = entry.lnum
      else
        for _, e in ipairs(buffer_entries(bufnr)) do
          if e.kind == "kv" and e.key == k then
            target_lnum = e.lnum
            break
          end
        end
      end

      if target_lnum then
        vim.api.nvim_buf_set_lines(bufnr, target_lnum - 1, target_lnum, false, { new_line })
      else
        local last = vim.api.nvim_buf_line_count(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, last, last, false, { new_line })
      end

      rescan(bufnr, config)
      vim.notify(("keychain.nvim: stored '%s' in the macOS Keychain"):format(k), vim.log.levels.INFO)
    end)
  end

  if key then
    proceed(key)
  else
    vim.ui.input({ prompt = "Key name to store: " }, proceed)
  end
end

---@param config KeychainConfig
function M.get(config, arg_key)
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local key = resolve_key(bufnr, arg_key)

  if not key then
    vim.notify("keychain.nvim: place cursor on a KEY=... line or pass :KeychainGet KEY", vim.log.levels.WARN)
    return
  end

  local service = project.service(config, path)
  local ok, value_or_err = macos.get(service, key)
  if not ok then
    vim.notify("keychain.nvim: " .. value_or_err, vim.log.levels.ERROR)
    return
  end

  ui.reveal(value_or_err, {
    title = "Keychain: " .. key,
    seconds = config.reveal_seconds,
    register = config.scratch_register,
  })
end

---@param config KeychainConfig
function M.delete(config, arg_key)
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local key = resolve_key(bufnr, arg_key)

  if not key then
    vim.notify("keychain.nvim: place cursor on a KEY=... line or pass :KeychainDelete KEY", vim.log.levels.WARN)
    return
  end

  if not ui.confirm(("Delete Keychain entry for '%s'? This cannot be undone."):format(key)) then
    return
  end

  local service = project.service(config, path)
  local ok, err = macos.delete(service, key)
  if ok then
    vim.notify(("keychain.nvim: deleted '%s' from the Keychain"):format(key), vim.log.levels.INFO)
  else
    vim.notify("keychain.nvim: " .. err, vim.log.levels.ERROR)
  end
end

---@param config KeychainConfig
function M.migrate(config)
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local entries = buffer_entries(bufnr)
  local flagged = detect.scan(entries, config)

  if #flagged == 0 then
    vim.notify("keychain.nvim: no plaintext secrets detected in this buffer", vim.log.levels.INFO)
    return
  end

  local service = project.service(config, path)
  local moved, skipped, failed = 0, 0, 0

  for _, item in ipairs(flagged) do
    local entry = item.entry
    local choice = vim.fn.confirm(
      string.format("Move '%s' to the Keychain?\n%s", entry.key, item.reason),
      "&Yes\n&No\n&Quit",
      1
    )

    if choice == 3 or choice == 0 then
      break
    elseif choice == 2 then
      skipped = skipped + 1
    else
      local ok, err = macos.set(service, entry.key, entry.value)
      if ok then
        local new_line = env.render_ref_line(entry.key, entry.key, { export = entry.export })
        vim.api.nvim_buf_set_lines(bufnr, entry.lnum - 1, entry.lnum, false, { new_line })
        moved = moved + 1
      else
        vim.notify(("keychain.nvim: failed to store '%s': %s"):format(entry.key, err), vim.log.levels.ERROR)
        failed = failed + 1
      end
    end
  end

  rescan(bufnr, config)
  vim.notify(
    string.format("keychain.nvim: migrate done - moved %d, skipped %d, failed %d", moved, skipped, failed),
    vim.log.levels.INFO
  )
end

---Load every `keychain://` reference (and plain value) from the current
---.env buffer directly into `vim.env` for this Neovim session, instead of
---writing a resolved file to disk. Only processes started from Neovim
---*after* this runs (e.g. `:terminal`, `jobstart()`) will inherit these -
---already-running terminals/jobs won't see the update.
---@param config KeychainConfig
function M.load(config)
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)

  if path == "" then
    vim.notify("keychain.nvim: save this .env file before running :KeychainLoad", vim.log.levels.WARN)
    return
  end

  local entries = buffer_entries(bufnr)
  local service = project.service(config, path)

  local resolved, errors = env.resolve_values(entries, function(account)
    return macos.get(service, account)
  end)

  for _, kv in ipairs(resolved) do
    vim.env[kv.key] = kv.value
    loaded_keys[kv.key] = true
  end

  local error_count = vim.tbl_count(errors)
  local level = error_count > 0 and vim.log.levels.WARN or vim.log.levels.INFO
  vim.notify(
    string.format(
      "keychain.nvim: loaded %d env var(s) into this Neovim session (%d unresolved). "
        .. "Only :terminal/jobs started after this will inherit them - run :KeychainUnload to clear.",
      #resolved,
      error_count
    ),
    level
  )
end

---Unset every env var previously set by :KeychainLoad in this session.
function M.unload()
  local keys = vim.tbl_keys(loaded_keys)
  table.sort(keys)

  for _, key in ipairs(keys) do
    vim.env[key] = nil
    loaded_keys[key] = nil
  end

  vim.notify(
    string.format("keychain.nvim: unloaded %d env var(s) from this Neovim session", #keys),
    vim.log.levels.INFO
  )
end

---@param root string
---@param target_path string
---@return string
local function relative_path(root, target_path)
  local prefix = vim.fn.resolve(root) .. "/"
  local resolved = vim.fn.resolve(target_path)
  if resolved:sub(1, #prefix) == prefix then
    return resolved:sub(#prefix + 1)
  end
  return target_path
end

---@param config KeychainConfig
function M.sync(config, arg_target)
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)

  if path == "" then
    vim.notify("keychain.nvim: save this .env file before running :KeychainSync", vim.log.levels.WARN)
    return
  end

  local entries = buffer_entries(bufnr)
  local service = project.service(config, path)

  local resolved_lines, errors = env.resolve_entries(entries, function(account)
    return macos.get(service, account)
  end)

  local final_lines = {}
  if config.sync.add_marker then
    final_lines[#final_lines + 1] = env.generated_marker()
  end
  vim.list_extend(final_lines, resolved_lines)

  local dir = vim.fn.fnamemodify(path, ":h")
  local target = (arg_target and arg_target ~= "") and arg_target or config.sync.target
  local target_path = target:match("^/") and target or (dir .. "/" .. target)

  local write_ok = pcall(vim.fn.writefile, final_lines, target_path)
  if not write_ok then
    vim.notify("keychain.nvim: failed to write " .. target_path, vim.log.levels.ERROR)
    return
  end

  local error_count = vim.tbl_count(errors)
  local level = error_count > 0 and vim.log.levels.WARN or vim.log.levels.INFO
  vim.notify(
    string.format("keychain.nvim: synced %s (%d unresolved)", target_path, error_count),
    level
  )

  if config.sync.auto_gitignore then
    local root = project.id(config, path)
    local gitignore_path = root .. "/.gitignore"
    local relpath = relative_path(root, target_path)

    local gitignore_lines = {}
    if vim.fn.filereadable(gitignore_path) == 1 then
      gitignore_lines = vim.fn.readfile(gitignore_path)
    end

    if not env.is_gitignored(gitignore_lines, relpath) then
      if ui.confirm(("Add '%s' to %s?"):format(relpath, gitignore_path)) then
        local new_lines = env.add_to_gitignore(gitignore_lines, relpath)
        vim.fn.writefile(new_lines, gitignore_path)
        vim.notify("keychain.nvim: added " .. relpath .. " to .gitignore", vim.log.levels.INFO)
      end
    end
  end
end

---@param config KeychainConfig
function M.setup(config)
  vim.api.nvim_create_user_command("KeychainSet", function(cmd_opts)
    M.set(config, cmd_opts.args ~= "" and cmd_opts.args or nil)
  end, { nargs = "?", desc = "Store a secret in the macOS Keychain and reference it from .env" })

  vim.api.nvim_create_user_command("KeychainGet", function(cmd_opts)
    M.get(config, cmd_opts.args ~= "" and cmd_opts.args or nil)
  end, { nargs = "?", desc = "Reveal a secret from the macOS Keychain" })

  vim.api.nvim_create_user_command("KeychainDelete", function(cmd_opts)
    M.delete(config, cmd_opts.args ~= "" and cmd_opts.args or nil)
  end, { nargs = "?", desc = "Delete a secret from the macOS Keychain" })

  vim.api.nvim_create_user_command("KeychainMigrate", function()
    M.migrate(config)
  end, { desc = "Move detected plaintext secrets in this buffer into the Keychain" })

  vim.api.nvim_create_user_command("KeychainSync", function(cmd_opts)
    M.sync(config, cmd_opts.args ~= "" and cmd_opts.args or nil)
  end, { nargs = "?", complete = "file", desc = "Resolve keychain:// refs into a real env file" })

  vim.api.nvim_create_user_command("KeychainLoad", function()
    M.load(config)
  end, { desc = "Load keychain:// refs from this buffer into vim.env (no file written)" })

  vim.api.nvim_create_user_command("KeychainUnload", function()
    M.unload()
  end, { desc = "Unset env vars previously set by :KeychainLoad" })
end

return M
