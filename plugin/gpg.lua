local gpgGroup = vim.api.nvim_create_augroup("customGpg", { clear = true })

vim.api.nvim_create_autocmd({ "BufReadPre", "FileReadPre" }, {
  pattern = "*.gpg",
  group = gpgGroup,
  callback = function()
    -- Make sure nothing is written to shada file while editing an encrypted file.
    vim.opt_local.shada = nil
    -- We don't want a swap file, as it writes unencrypted data to disk
    vim.opt_local.swapfile = false
    -- Switch to binary mode to read the encrypted file
    vim.opt_local.bin = true

    -- Save the current 'ch' value to a buffer-local variable
    vim.b.ch_save = vim.o.ch
    vim.o.ch = 2
  end,
})

vim.api.nvim_create_autocmd({ "BufReadPost", "FileReadPost" }, {
  pattern = "*.gpg",
  group = gpgGroup,
  callback = function()
    vim.cmd "'[,']!gpg --decrypt 2> /dev/null"

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
  command = "'[,']!gpg --default-recipient-self -ae 2>/dev/null",
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
