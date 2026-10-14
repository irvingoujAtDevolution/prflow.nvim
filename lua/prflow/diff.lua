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

-- Splits a line into words, whitespace runs and single characters,
-- each as { text, start_col, end_col } (0-based, end exclusive).
local function tokens(line)
  local out, pos = {}, 1
  while pos <= #line do
    local _, e = line:find('^[%w_]+', pos)
    e = e or select(2, line:find('^%s+', pos)) or select(2, line:find('^[\192-\247][\128-\191]*', pos)) or pos
    out[#out + 1] = { line:sub(pos, e), pos - 1, e }
    pos = e + 1
  end
  return out
end

local function texts(toks)
  return vim.tbl_map(function(t)
    return t[1]
  end, toks)
end

-- Changed byte ranges { start_col, end_col } between two versions of a line.
function M.words(old, new)
  local a, b = tokens(old), tokens(new)
  local old_ranges, new_ranges = {}, {}
  for _, h in ipairs(textdiff(join(texts(a)), join(texts(b)), { result_type = 'indices' })) do
    if h[2] > 0 then
      old_ranges[#old_ranges + 1] = { a[h[1]][2], a[h[1] + h[2] - 1][3] }
    end
    if h[4] > 0 then
      new_ranges[#new_ranges + 1] = { b[h[3]][2], b[h[3] + h[4] - 1][3] }
    end
  end
  return old_ranges, new_ranges
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
