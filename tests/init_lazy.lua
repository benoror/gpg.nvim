local root = vim.fn.fnamemodify(vim.fn.expand("<sfile>"), ":p:h:h")
package.path = root .. "/?.lua;" .. package.path

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    error("Failed to clone lazy.nvim")
  end
end

vim.opt.runtimepath:prepend(lazypath)
require("lazy").setup({ { dir = root } }, { root = vim.fn.stdpath("data") .. "/lazy" })
