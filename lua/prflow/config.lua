local M = {}

M.defaults = {
  -- nil: origin/HEAD's branch, else origin/main, else origin/master.
  base = nil,
  debounce_ms = 150,
  show_viewed = false,
  keys = {
    next = ']h',
    prev = '[h',
    hunk = '<leader>hd',
    viewed = '<leader>hv',
    tree = '<leader>ht',
  },
}

function M.get()
  return vim.tbl_deep_extend('force', M.defaults, vim.g.prflow or {})
end

return M
