local diff = require('prflow.diff')

local M = {}

M.ns = vim.api.nvim_create_namespace('prflow')

local links = {
  PrflowAdd = 'DiffAdd',
  PrflowDelete = 'DiffDelete',
  PrflowAddText = 'DiffText',
  PrflowDeleteText = 'DiffText',
  PrflowAddSign = 'Added',
  PrflowDeleteSign = 'Removed',
  PrflowChangeSign = 'Changed',
  PrflowViewed = 'Comment',
}

function M.define_highlights()
  for name, link in pairs(links) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

M.define_highlights()

local signs = {
  add = { '+', 'PrflowAddSign' },
  change = { '~', 'PrflowChangeSign' },
  delete = { '-', 'PrflowDeleteSign' },
}

local function style(h, viewed)
  if viewed then
    return { line = 'PrflowViewed', del = 'PrflowViewed', words = false, sign = signs[h.kind][1], sign_hl = 'PrflowViewed' }
  end
  return { line = 'PrflowAdd', del = 'PrflowDelete', words = true, sign = signs[h.kind][1], sign_hl = signs[h.kind][2] }
end

-- A deleted line as virt_line chunks, changed words in `PrflowDeleteText`.
local function virt_line(buf, text, ranges, hl)
  local tab = string.rep(' ', vim.bo[buf].tabstop)
  local chunks, width, pos = {}, 0, 0
  local function push(s, e, group)
    if e > s then
      local piece = text:sub(s + 1, e):gsub('\t', tab)
      chunks[#chunks + 1] = { piece, group }
      width = width + vim.fn.strdisplaywidth(piece)
    end
  end
  for _, r in ipairs(ranges or {}) do
    push(pos, r[1], hl)
    push(r[1], r[2], 'PrflowDeleteText')
    pos = r[2]
  end
  push(pos, #text, hl)
  chunks[#chunks + 1] = { string.rep(' ', math.max(0, vim.o.columns - width)), hl }
  return chunks
end

local function mark(buf, row, opts, col)
  vim.api.nvim_buf_set_extmark(buf, M.ns, row, col or 0, opts)
end

-- The scratch buffer of a deleted file shows the base content, every line deleted.
local function render_deleted(buf, st)
  for row = 0, vim.api.nvim_buf_line_count(buf) - 1 do
    mark(buf, row, { line_hl_group = st.del, sign_text = st.sign, sign_hl_group = st.sign_hl })
  end
end

local function render_hunk(buf, h, line_count, st)
  for i = 0, h.new_count - 1 do
    local row = h.new_start - 1 + i
    -- Not line_hl_group: it paints over the word highlights below at any priority.
    mark(buf, row, {
      end_row = row + 1,
      end_col = 0,
      strict = false,
      hl_group = st.line,
      hl_eol = true,
      priority = 100,
      sign_text = st.sign,
      sign_hl_group = st.sign_hl,
    })
  end
  if h.old_count == 0 then
    return
  end
  -- Old and new lines are paired by position inside a changed hunk.
  local old_words = {}
  if h.kind == 'change' and st.words then
    for i = 1, math.min(h.old_count, h.new_count) do
      local old_ranges, new_ranges = diff.words(h.old_lines[i], h.new_lines[i])
      old_words[i] = old_ranges
      for _, r in ipairs(new_ranges) do
        mark(buf, h.new_start + i - 2, { end_col = r[2], hl_group = 'PrflowAddText', priority = 200 }, r[1])
      end
    end
  end
  local virt = {}
  for i, l in ipairs(h.old_lines) do
    virt[#virt + 1] = virt_line(buf, l, old_words[i], st.del)
  end
  local row, above = h.top - 1, true
  if row >= line_count then
    row, above = line_count - 1, false
  end
  local opts = { virt_lines = virt, virt_lines_above = above }
  if h.kind == 'delete' then
    opts.sign_text, opts.sign_hl_group = st.sign, st.sign_hl
  end
  mark(buf, row, opts)
end

function M.buf(buf, file)
  local core = require('prflow.core')
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  local hunks = file.hunks or {}
  if file.status == 'D' then
    return hunks[1] and render_deleted(buf, style(hunks[1], core.is_viewed(hunks[1])))
  end
  local line_count = vim.api.nvim_buf_line_count(buf)
  for _, h in ipairs(hunks) do
    render_hunk(buf, h, line_count, style(h, core.is_viewed(h)))
  end
end

function M.clear_all()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    end
  end
end

return M
