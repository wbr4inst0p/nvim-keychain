-- Derives a stable per-project identifier so that the same env key name
-- (e.g. DATABASE_PASSWORD) used in two different projects never collides in
-- the shared macOS Keychain.
local M = {}

---@param start_path string Absolute path to start searching upward from.
---@return string
local function find_git_root(start_path)
  local root = vim.fs.root(start_path, { ".git" })
  return root or vim.fn.getcwd()
end

---@param config KeychainConfig
---@param path string|nil Absolute file path (defaults to the current buffer's path or cwd).
---@return string project_id
function M.id(config, path)
  path = path or vim.api.nvim_buf_get_name(0)
  if path == "" then
    path = vim.fn.getcwd()
  end
  local dir = vim.fn.fnamemodify(path, ":p:h")

  local id
  if config.project_id_strategy == "git_root" then
    id = find_git_root(dir)
  else
    id = vim.fn.getcwd()
  end

  return vim.fn.resolve(id)
end

---Build the keychain "service" string for the project that owns `path`.
---@param config KeychainConfig
---@param path string|nil
---@return string
function M.service(config, path)
  return config.service_prefix .. M.id(config, path)
end

return M
