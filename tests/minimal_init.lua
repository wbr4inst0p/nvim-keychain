-- Minimal init used to run the plenary test suite:
--   PLENARY_PATH=/path/to/plenary.nvim \
--     nvim --headless -u tests/minimal_init.lua \
--     -c "PlenaryBustedDirectory tests/keychain/ { minimal_init = 'tests/minimal_init.lua' }"
--
-- PLENARY_PATH defaults to the common lazy.nvim install location if unset.

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(plugin_root)

local plenary_path = os.getenv("PLENARY_PATH")
  or (vim.fn.stdpath("data") .. "/lazy/plenary.nvim")
  or (vim.fn.stdpath("data") .. "/site/pack/packer/start/plenary.nvim")

if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.rtp:prepend(plenary_path)
end

vim.cmd("runtime plugin/plenary.vim")
