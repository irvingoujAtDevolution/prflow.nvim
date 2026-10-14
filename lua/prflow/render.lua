local M = {}

M.ns = vim.api.nvim_create_namespace('prflow')

local links = {
  PrflowAdd = 'DiffAdd',
  PrflowDelete = 'DiffDelete',
  PrflowAddSign = 'Added',
  PrflowDeleteSign = 'Removed',
  PrflowChangeSign = 'Changed',
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

local function virt_line(buf, text)
  text = text:gsub('\t', string.rep(' ', vim.bo[buf].tabstop))
  local pad = math.max(0, vim.o.columns - vim.fn.strdisplaywidth(text))
  return { { text .. string.rep(' ', pad), 'PrflowDelete' } }
end

local function mark(buf, row, opts)
  vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, opts)
end

-- The scratch buffer of a deleted file shows the base content, every line deleted.
local function render_deleted(buf)
  local sign = signs.delete
  for row = 0, vim.api.nvim_buf_line_count(buf) - 1 do
    mark(buf, row, { line_hl_group = 'PrflowDelete', sign_text = sign[1], sign_hl_group = sign[2] })
  end
end

local function render_hunk(buf, h, line_count)
  local sign = signs[h.kind]
  for i = 0, h.new_count - 1 do
    mark(buf, h.new_start - 1 + i, { line_hl_group = 'PrflowAdd', sign_text = sign[1], sign_hl_group = sign[2] })
  end
  if h.old_count == 0 then
    return
  end
  local virt = {}
  for _, l in ipairs(h.old_lines) do
    virt[#virt + 1] = virt_line(buf, l)
  end
  local row, above = h.top - 1, true
  if row >= line_count then
    row, above = line_count - 1, false
  end
  local opts = { virt_lines = virt, virt_lines_above = above }
  if h.kind == 'delete' then
    opts.sign_text, opts.sign_hl_group = sign[1], sign[2]
  end
  mark(buf, row, opts)
end

function M.buf(buf, file)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  if file.status == 'D' then
    return render_deleted(buf)
  end
  local line_count = vim.api.nvim_buf_line_count(buf)
  for _, h in ipairs(file.hunks or {}) do
    render_hunk(buf, h, line_count)
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
