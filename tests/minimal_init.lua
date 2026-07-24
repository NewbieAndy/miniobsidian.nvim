local plugin_root = vim.env.MINIOBSIDIAN_ROOT or vim.fn.getcwd()
local plenary_root = vim.env.PLENARY_DIR or (vim.fn.stdpath("data") .. "/lazy/plenary.nvim")

vim.opt.runtimepath:prepend(plugin_root)
vim.opt.runtimepath:prepend(plenary_root)
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"

vim.notify = function() end
