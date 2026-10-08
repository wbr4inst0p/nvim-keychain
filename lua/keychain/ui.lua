-- Small UI helpers: a masked single-line input for typing secrets, and an
-- auto-clearing "reveal" window for showing a fetched secret briefly.
local M = {}

local function centered_geometry(width, height)
  return {
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
  }
end

---Prompt for a secret value using a floating input whose characters are
---masked with `*` as you type (via conceal), so it never touches
---`vim.fn.input`'s persisted history.
---@param opts {prompt: string|nil, width: integer|nil}
---@param callback fun(value: string|nil) Called with the typed value, or nil if cancelled.
function M.input_secret(opts, callback)
  opts = opts or {}
  local prompt = opts.prompt or "Secret value"
  local width = opts.width or math.max(40, #prompt + 10)
  local height = 1

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false

  local geo = centered_geometry(width, height)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = geo.row,
    col = geo.col,
    style = "minimal",
    border = "rounded",
    title = " " .. prompt .. " (<CR> confirm, <Esc> cancel) ",
    title_pos = "center",
  })

  vim.wo[win].conceallevel = 2
  vim.wo[win].concealcursor = "nvic"
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("syntax match KeychainMask /./ conceal cchar=*")
  end)

  local done = false
  local function finish(value)
    if done then
      return
    end
    done = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    callback(value)
  end

  vim.keymap.set({ "i", "n" }, "<CR>", function()
    local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    finish(line ~= "" and line or nil)
  end, { buffer = buf, nowait = true })

  vim.keymap.set({ "i", "n" }, "<Esc>", function()
    finish(nil)
  end, { buffer = buf, nowait = true })

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = function()
      finish(nil)
    end,
  })

  vim.cmd("startinsert")
end

---Show a value briefly in a floating window and stash it in a register,
---clearing both after `seconds`.
---@param value string
---@param opts {title: string|nil, seconds: number|nil, register: string|nil}
function M.reveal(value, opts)
  opts = opts or {}
  local seconds = opts.seconds or 10
  local register = opts.register or "z"
  local title = opts.title or "Keychain secret"

  vim.fn.setreg(register, value)

  local width = math.max(#value + 4, #title + 4, 20)
  local height = 1
  local geo = centered_geometry(width, height)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { value })

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = geo.row,
    col = geo.col,
    style = "minimal",
    border = "rounded",
    title = string.format(" %s (register @%s, clears in %ds) ", title, register, seconds),
    title_pos = "center",
  })

  local function close_and_clear()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.fn.getreg(register) == value then
      vim.fn.setreg(register, "")
    end
  end

  vim.keymap.set("n", "q", close_and_clear, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close_and_clear, { buffer = buf, nowait = true })

  vim.defer_fn(close_and_clear, seconds * 1000)

  vim.notify(
    string.format("keychain.nvim: value yanked to register @%s (auto-clears in %ds)", register, seconds),
    vim.log.levels.INFO
  )
end

---@param prompt string
---@param choices string|nil e.g. "&Yes\n&No"
---@param default integer|nil
---@return boolean
function M.confirm(prompt, choices, default)
  local ok, ret = pcall(vim.fn.confirm, prompt, choices or "&Yes\n&No", default or 2)
  return ok and ret == 1
end

return M
