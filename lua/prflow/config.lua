local M = {}

M.defaults = {
  base = 'origin/main',
  debounce_ms = 150,
  show_viewed = false,
  keys = {
    next = ']h',
    prev = '[h',
    hunk = '<leader>hd',
    viewed = '<leader>hv',
  },
}

function M.get()
  return vim.tbl_deep_extend('force', M.defaults, vim.g.prflow or {})
end

return M
