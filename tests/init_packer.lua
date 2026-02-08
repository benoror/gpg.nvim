local root = vim.fn.fnamemodify(vim.fn.expand("<sfile>"), ":p:h:h")
package.path = root .. "/?.lua;" .. package.path

local packer_path = vim.fn.stdpath("data") .. "/site/pack/packer/start/packer.nvim"
if not vim.loop.fs_stat(packer_path) then
  vim.fn.system({
    "git",
    "clone",
    "--depth",
    "1",
    "https://github.com/wbthomason/packer.nvim",
    packer_path,
  })
  if vim.v.shell_error ~= 0 then
    error("Failed to clone packer.nvim")
  end
end

vim.cmd("packadd packer.nvim")
local packer = require("packer")
local compile_path = vim.fn.stdpath("data") .. "/site/plugin/packer_compiled_test.lua"
local package_root = vim.fn.stdpath("data") .. "/site/pack/packer-test"
packer.init({ compile_path = compile_path, package_root = package_root })
packer.startup(function(use)
  use(root)
end)

vim.g.packer_sync_done = false
vim.api.nvim_create_autocmd("User", {
  pattern = "PackerComplete",
  once = true,
  callback = function()
    vim.g.packer_sync_done = true
  end,
})

packer.sync()
vim.wait(10000, function()
  return vim.g.packer_sync_done
end, 100)

packer.compile()
if vim.fn.filereadable(compile_path) == 0 then
  error("packer compile output missing at " .. compile_path)
end
vim.cmd("source " .. compile_path)
