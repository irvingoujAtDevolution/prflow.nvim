local M = {}

local textdiff = (vim.text and vim.text.diff) or vim.diff

local function join(lines)
  if #lines == 0 then
    return ''
  end
  return table.concat(lines, '\n') .. '\n'
end

function M.hash(path, old_lines, new_lines)
  return vim.fn.sha256(path .. '\n@@old\n' .. table.concat(old_lines, '\n') .. '\n@@new\n' .. table.concat(new_lines, '\n'))
end

-- Line hunks between `old` and `new`. `top` is the buffer line a hunk is
-- anchored to: its first new line, or the line after a pure deletion.
function M.hunks(path, old, new)
  local out = {}
  for _, h in ipairs(textdiff(join(old), join(new), { result_type = 'indices' })) do
    local os, oc, ns, nc = h[1], h[2], h[3], h[4]
    local old_lines = vim.list_slice(old, os, os + oc - 1)
    local new_lines = vim.list_slice(new, ns, ns + nc - 1)
    out[#out + 1] = {
      old_start = os,
      old_count = oc,
      new_start = ns,
      new_count = nc,
      old_lines = old_lines,
      new_lines = new_lines,
      kind = oc == 0 and 'add' or nc == 0 and 'delete' or 'change',
      top = nc > 0 and ns or ns + 1,
      hash = M.hash(path, old_lines, new_lines),
    }
  end
  return out
end

return M
