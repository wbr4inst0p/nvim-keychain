-- vim.diagnostic integration: flags plaintext-looking secrets in .env buffers.
-- Passive only - never blocks saving.
local env = require("keychain.env")
local detect = require("keychain.detect")

local M = {}

M.namespace = vim.api.nvim_create_namespace("keychain")

local timers = {}

---@param bufname string
---@param config KeychainConfig
---@return boolean
function M.is_env_buffer(bufname, config)
  if bufname == nil or bufname == "" then
    return false
  end
  local tail = vim.fn.fnamemodify(bufname, ":t"):lower()

  for _, pattern in ipairs(config.env_file_ignore_patterns) do
    if tail:match(pattern) then
      return false
    end
  end
  for _, pattern in ipairs(config.env_file_patterns) do
    if tail:match(pattern) then
      return true
    end
  end
  return false
end

---Scan the buffer immediately (no debounce) and update its diagnostics.
---@param bufnr integer
---@param config KeychainConfig
function M.scan_buffer(bufnr, config)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if not M.is_env_buffer(bufname, config) then
    vim.diagnostic.reset(M.namespace, bufnr)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if env.has_generated_marker(lines) then
    vim.diagnostic.reset(M.namespace, bufnr)
    return
  end

  local entries = env.parse_lines(lines)
  local flagged = detect.scan(entries, config)

  local diagnostics = {}
  for _, item in ipairs(flagged) do
    diagnostics[#diagnostics + 1] = {
      lnum = item.entry.lnum - 1,
      col = 0,
      end_col = #item.entry.raw,
      severity = vim.diagnostic.severity.WARN,
      source = "keychain",
      message = item.reason,
    }
  end

  vim.diagnostic.set(M.namespace, bufnr, diagnostics)
end

---@param bufnr integer
---@param config KeychainConfig
---@param delay_ms integer
local function debounced_scan(bufnr, config, delay_ms)
  local timer = timers[bufnr]
  if not timer then
    timer = vim.uv.new_timer()
    timers[bufnr] = timer
  end
  timer:stop()
  timer:start(
    delay_ms,
    0,
    vim.schedule_wrap(function()
      M.scan_buffer(bufnr, config)
    end)
  )
end

local function cleanup_timer(bufnr)
  local timer = timers[bufnr]
  if timer then
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
    timers[bufnr] = nil
  end
end

---Install autocmds that keep diagnostics for .env buffers up to date.
---@param config KeychainConfig
function M.setup(config)
  local group = vim.api.nvim_create_augroup("KeychainDiagnostics", { clear = true })

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufEnter" }, {
    group = group,
    callback = function(args)
      debounced_scan(args.buf, config, 50)
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave", "BufWritePost" }, {
    group = group,
    callback = function(args)
      debounced_scan(args.buf, config, 300)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(args)
      cleanup_timer(args.buf)
    end,
  })
end

return M
