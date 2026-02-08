local gpgGroup = vim.api.nvim_create_augroup("customGpg", { clear = true })

local function get_gpg_tty()
  local gpg_tty = vim.env.GPG_TTY
  if not gpg_tty or gpg_tty == "" then
    local tty = vim.trim(vim.fn.system "tty")
    if tty ~= "" and not tty:match("not a tty") then
      gpg_tty = tty
    end
  end
  return gpg_tty
end

local function update_gpg_tty()
  if vim.g.gpg_update_tty ~= true then
    return
  end
  local gpg_tty = get_gpg_tty()
  if not gpg_tty or gpg_tty == "" then
    return
  end
  vim.env.GPG_TTY = gpg_tty
  local result = vim.system({ "gpg-connect-agent", "updatestartuptty", "/bye" }):wait()
  if result.code ~= 0 and vim.g.gpg_update_tty_verbose then
    vim.notify("gpg-connect-agent failed: " .. (result.stderr or ""), vim.log.levels.WARN)
  end
end

local function prime_gpg_agent(file_path)
  if vim.g.gpg_prime_agent ~= true then
    return
  end
  if file_path == "" then
    return
  end
  local escaped = vim.fn.shellescape(file_path)
  vim.cmd("silent! !gpg --quiet --list-packets " .. escaped .. " >/dev/null 2>&1")
  vim.cmd "redraw!"
end

vim.api.nvim_create_autocmd({ "BufReadPre", "FileReadPre" }, {
  pattern = "*.gpg",
  group = gpgGroup,
  callback = function()
    -- Make sure nothing is written to shada file while editing an encrypted file.
    vim.opt.shada = ""
    -- We don't want a swap file, as it writes unencrypted data to disk
    vim.opt_local.swapfile = false
    -- Switch to binary mode to read the encrypted file
    vim.opt_local.bin = true
    -- Disable undofile as it stores unencrypted data on your disk
    vim.opt_local.undofile = false
    -- Also avoid backups for this buffer
    vim.opt_local.backup = false
    vim.opt_local.writebackup = false

    -- Save the current 'ch' value to a buffer-local variable
    vim.b.ch_save = vim.o.ch
    vim.o.ch = 2
  end,
})

vim.api.nvim_create_autocmd({ "BufReadPost", "FileReadPost" }, {
  pattern = "*.gpg",
  group = gpgGroup,
  callback = function()
    update_gpg_tty()
    prime_gpg_agent(vim.fn.expand "%:p")
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local input = table.concat(lines, "\n")
    local result = vim.system({ "gpg", "--decrypt" }, { stdin = input }):wait()
    if result.code ~= 0 then
      vim.notify("gpg decrypt failed: " .. (result.stderr or ""), vim.log.levels.ERROR)
      return
    end
    local output_lines = vim.split(result.stdout, "\n", { plain = true })
    if #output_lines > 0 and output_lines[#output_lines] == "" then
      table.remove(output_lines, #output_lines)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, output_lines)
    vim.api.nvim_buf_set_option(buf, "modified", false)

    -- Switch to normal mode for editing
    vim.opt_local.bin = false

    -- Restore the 'ch' value from the buffer-local variable
    vim.o.ch = vim.b.ch_save
    vim.b.ch_save = nil
    vim.api.nvim_exec_autocmds("BufReadPost", { pattern = vim.fn.expand "%:r" })
  end,
})

-- Convert all text to encrypted text before writing
vim.api.nvim_create_autocmd({ "BufWritePre", "FileWritePre" }, {
  pattern = "*.gpg",
  group = gpgGroup,
  callback = function()
    update_gpg_tty()
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local input = table.concat(lines, "\n")
    local result = vim.system({ "gpg", "--default-recipient-self", "-ae" }, { stdin = input }):wait()
    if result.code ~= 0 then
      vim.notify("gpg encrypt failed: " .. (result.stderr or ""), vim.log.levels.ERROR)
      return
    end
    local output_lines = vim.split(result.stdout, "\n", { plain = true })
    if #output_lines > 0 and output_lines[#output_lines] == "" then
      table.remove(output_lines, #output_lines)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, output_lines)
    vim.api.nvim_buf_set_option(buf, "modified", false)
  end,
})
-- Undo the encryption so we are back in the normal text, directly
-- after the file has been written.
vim.api.nvim_create_autocmd({ "BufWritePost", "FileWritePost" }, {
  pattern = "*.gpg",
  group = gpgGroup,
  command = "u",
})

-- Return an empty table to satisfy plugin loader requirements
return {}
