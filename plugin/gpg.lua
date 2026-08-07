local gpgGroup = vim.api.nvim_create_augroup("customGpg", { clear = true })

local function loopback_enabled()
  return vim.g.gpg_pinentry_loopback ~= false
end

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

local function normalize_gpg_stdout(stdout)
  local output_lines = vim.split(stdout or "", "\n", { plain = true })
  if #output_lines > 0 and output_lines[#output_lines] == "" then
    table.remove(output_lines, #output_lines)
  end
  return output_lines
end

-- Detect decrypt failures that mean gpg wants a passphrase from the caller.
local function needs_passphrase(stderr)
  local s = stderr or ""
  return s:find("can't get input", 1, true)
    or s:find("No passphrase given", 1, true)
    or s:find("Bad passphrase", 1, true)
    or s:find("passphrase", 1, true)
    or s:find("pinentry", 1, true)
    or s:find("Pinentry", 1, true)
    or s:find("Inappropriate ioctl", 1, true)
    or s:find("public key decryption failed", 1, true)
end

local function prompt_passphrase()
  local ok, value = pcall(vim.fn.inputsecret, "GPG passphrase: ")
  if not ok then
    return nil, "passphrase prompt cancelled"
  end
  return value, nil
end

local function gpg_decrypt_loopback(ciphertext, file_path)
  -- First try: agent cache / unprotected keys. Never invokes pinentry UIs.
  local result = vim.system({
    "gpg",
    "--batch",
    "--yes",
    "--pinentry-mode",
    "loopback",
    "--decrypt",
  }, { stdin = ciphertext }):wait()

  if result.code == 0 then
    return result
  end

  if not needs_passphrase(result.stderr) then
    return result
  end

  if not file_path or file_path == "" then
    result.stderr = (result.stderr or "")
      .. "\ngpg.nvim: passphrase required but buffer has no file path"
    return result
  end

  local passphrase, prompt_err = prompt_passphrase()
  if prompt_err then
    result.code = 1
    result.stderr = prompt_err
    return result
  end

  -- Passphrase on stdin (fd 0); ciphertext from the on-disk encrypted file.
  result = vim.system({
    "gpg",
    "--batch",
    "--yes",
    "--pinentry-mode",
    "loopback",
    "--passphrase-fd",
    "0",
    "--decrypt",
    "--",
    file_path,
  }, { stdin = passphrase .. "\n" }):wait()

  return result
end

local function gpg_decrypt_legacy(ciphertext)
  return vim.system({ "gpg", "--decrypt" }, { stdin = ciphertext }):wait()
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
    local file_path = vim.fn.expand "%:p"
    prime_gpg_agent(file_path)
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local input = table.concat(lines, "\n")

    local result
    if loopback_enabled() then
      result = gpg_decrypt_loopback(input, file_path)
    else
      result = gpg_decrypt_legacy(input)
    end

    if result.code ~= 0 then
      vim.notify("gpg decrypt failed: " .. (result.stderr or ""), vim.log.levels.ERROR)
      return
    end
    local output_lines = normalize_gpg_stdout(result.stdout)
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
    local output_lines = normalize_gpg_stdout(result.stdout)
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
