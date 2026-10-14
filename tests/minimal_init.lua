local root = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h'))
vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(root .. '/deps/mini.nvim')
package.path = root .. '/?.lua;' .. package.path
vim.o.swapfile = false
vim.o.shadafile = 'NONE'
vim.g.prflow = vim.g.prflow or { auto = false }
vim.cmd('runtime plugin/prflow.lua')
require('mini.test').setup()
