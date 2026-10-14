-- One ordered hunk stream across every changed file.
local core = require('prflow.core')

local M = {}

function M.order(files)
  local out = vim.list_slice(files)
  table.sort(out, function(a, b)
    return a.path < b.path
  end)
  return out
end

function M.eligible(_)
  return true
end

local function find_in(file, from, dir)
  local hunks = core.ensure_hunks(file)
  local first, last, step = 1, #hunks, 1
  if dir < 0 then
    first, last, step = #hunks, 1, -1
  end
  for i = first, last, step do
    local h = hunks[i]
    if (h.top - from) * dir > 0 and M.eligible(h) then
      return h
    end
  end
end

local function deleted_buf(file)
  local s = core.session
  local buf = s.scratch[file.path]
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  core.ensure_hunks(file)
  buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, 'prflow://deleted/' .. file.path)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, file.base_lines)
  vim.b[buf].prflow_path = file.path
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  local ft = vim.filetype.match({ filename = file.path })
  if ft then
    vim.bo[buf].filetype = ft
  end
  s.scratch[file.path] = buf
  return buf
end

function M.open(file)
  if file.status == 'D' then
    local buf = deleted_buf(file)
    vim.api.nvim_win_set_buf(0, buf)
    core.attach(buf)
  else
    vim.cmd.edit(vim.fn.fnameescape(core.abs(file.path)))
  end
end

function M.jump(file, h)
  if core.file_for_buf(vim.api.nvim_get_current_buf()) ~= file then
    M.open(file)
  end
  local line = math.min(math.max(h.top, 1), vim.api.nvim_buf_line_count(0))
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  -- Deleted lines above line 1 are only visible through 'topfill'.
  if h.top == 1 and h.old_count > 0 and file.status ~= 'D' then
    vim.fn.winrestview({ topline = 1, topfill = h.old_count })
  end
end

function M.step(dir)
  local s = core.session
  if not (s and s.ready) then
    return vim.notify('prflow: not in review mode', vim.log.levels.WARN)
  end
  local files, n = s.files, #s.files
  local file = core.file_for_buf(vim.api.nvim_get_current_buf())
  local idx = dir > 0 and 0 or n + 1
  if file then
    idx = file.index
    local h = find_in(file, vim.api.nvim_win_get_cursor(0)[1], dir)
    if h then
      return M.jump(file, h)
    end
  end
  for k = 1, n do
    local i = idx + dir * k
    local wrapped = i < 1 or i > n
    local f = files[(i - 1) % n + 1]
    local h = find_in(f, dir > 0 and 0 or math.huge, dir)
    if h then
      if wrapped then
        vim.notify(('prflow: wrapped to %s hunk'):format(dir > 0 and 'first' or 'last'))
      end
      return M.jump(f, h)
    end
  end
  vim.notify('prflow: no hunks to review')
end

-- The hunk the cursor is on, if any.
function M.hunk_at_cursor()
  local file = core.file_for_buf(vim.api.nvim_get_current_buf())
  if not file then
    return nil
  end
  local hunks = core.ensure_hunks(file)
  if file.status == 'D' then
    return file, hunks[1]
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local last = vim.api.nvim_buf_line_count(0)
  for _, h in ipairs(hunks) do
    local top = math.min(h.top, last)
    if (h.new_count > 0 and line >= h.new_start and line < h.new_start + h.new_count) or (h.new_count == 0 and line == top) then
      return file, h
    end
  end
  return file, nil
end

return M
