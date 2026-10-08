-- Load guard for plugin managers that source `plugin/*.lua` automatically.
-- This file intentionally does NOT call setup() itself: call
-- require("keychain").setup({...}) from your config (works for lazy.nvim,
-- packer, vim-plug, etc., and plays nicely with lazy-loading on commands).
if vim.g.loaded_keychain_nvim then
  return
end
vim.g.loaded_keychain_nvim = true

if vim.fn.has("nvim-0.10") == 0 then
  vim.notify("keychain.nvim requires Neovim >= 0.10", vim.log.levels.ERROR)
end
