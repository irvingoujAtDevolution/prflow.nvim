-- Sidebar listing the changed files by directory, in hunk-stream order.
local core = require('prflow.core')
require('prflow.render')

local M = {}

M.ns = vim.api.nvim_create_namespace('prflow_tree')

local state = { buf = nil, win = nil, target = nil, files = {} }

for name, link in pairs({
  PrflowTreeCurrent = 'Visual',
  PrflowTreeDir = 'Directory',
  PrflowTreeDone = 'Comment',
  PrflowTreeHeader = 'Title',
}) do
  vim.api.nvim_set_hl(0, name, { link = link, default = true })
end

local status_hl = { M = 'PrflowChangeSign', R = 'PrflowChangeSign', C = 'PrflowChangeSign', A = 'PrflowAddSign', D = 'PrflowDeleteSign' }

function M.buf()
  return state.buf
end

function M.win()
  return state.win
end

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

local function progress(file)
  if not file.hunks then
    return '?', false
  end
  local viewed = 0
  for _, h in ipairs(file.hunks) do
    if core.is_viewed(h) then
      viewed = viewed + 1
    end
  end
  return ('%d/%d'):format(viewed, #file.hunks), viewed == #file.hunks
end

-- Rows as { text, file?, dir?, done?, status_col? }; a directory row is emitted
-- whenever a file's parent path diverges from the previous file's.
local function rows(s)
  local out, prev = {}, {}
  for _, f in ipairs(s.files) do
    local parts = vim.split(f.path, '/', { plain = true })
    local name = table.remove(parts)
    local same = 0
    while same < #parts and parts[same + 1] == prev[same + 1] do
      same = same + 1
    end
    for i = same + 1, #parts do
      out[#out + 1] = { text = string.rep('  ', i - 1) .. parts[i] .. '/', dir = true }
    end
    prev = parts
    local added, removed = require('prflow.picker').counts(f)
    local prog, done = progress(f)
    local indent = string.rep('  ', #parts)
    out[#out + 1] = {
      left = indent .. f.status .. ' ' .. name,
      right = ('+%d -%d  %s'):format(added, removed, prog),
      file = f,
      done = done,
      status_col = #indent,
    }
  end
  return out
end

local function current_file()
  local win = M.target_win()
  return win and core.file_for_buf(vim.api.nvim_win_get_buf(win)) or nil
end

function M.refresh()
  if not M.is_open() then
    return
  end
  local s = core.session
  local lines, marks = {}, {}
  state.files = {}
  if not (s and s.ready) then
    lines = { 'prflow: loading...' }
  else
    lines[1] = ('%s vs %s'):format(s.branch, s.range.mode == 'base' and s.ref or s.range.mode)
    marks[#marks + 1] = { 0, 0, { end_col = #lines[1], hl_group = 'PrflowTreeHeader' } }
    local list = rows(s)
    local width = 0
    for _, r in ipairs(list) do
      width = math.max(width, vim.fn.strdisplaywidth(r.left or ''))
    end
    local current = current_file()
    for _, r in ipairs(list) do
      local row = #lines
      if r.dir then
        lines[#lines + 1] = r.text
        marks[#marks + 1] = { row, 0, { end_col = #r.text, hl_group = 'PrflowTreeDir' } }
      else
        local text = r.left .. string.rep(' ', width - vim.fn.strdisplaywidth(r.left) + 2) .. r.right
        lines[#lines + 1] = text
        state.files[row + 1] = r.file
        marks[#marks + 1] = { row, r.status_col, { end_col = r.status_col + 1, hl_group = status_hl[r.file.status] } }
        if r.done then
          marks[#marks + 1] = { row, r.status_col + 2, { end_col = #text, hl_group = 'PrflowTreeDone' } }
        end
        if r.file == current then
          marks[#marks + 1] = { row, 0, { line_hl_group = 'PrflowTreeCurrent' } }
        end
      end
    end
  end
  local buf = state.buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, M.ns, m[1], m[2], m[3])
  end
end

-- The window files open in: the one the tree was opened from, else any other.
function M.target_win()
  if state.target and vim.api.nvim_win_is_valid(state.target) and state.target ~= state.win then
    return state.target
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= state.win and vim.api.nvim_win_get_config(win).relative == '' then
      state.target = win
      return win
    end
  end
end

-- Called on WinEnter: files open in whichever normal window was used last.
function M.track(win)
  if win ~= state.win and vim.api.nvim_win_get_config(win).relative == '' then
    state.target = win
  end
end

-- Leaves the tree window so a jump never opens a file inside it.
function M.leave()
  if M.is_open() and vim.api.nvim_get_current_win() == state.win then
    local win = M.target_win()
    if not win then
      vim.cmd('rightbelow vsplit')
      win = vim.api.nvim_get_current_win()
      state.target = win
      vim.api.nvim_win_set_width(state.win, 40)
    end
    vim.api.nvim_set_current_win(win)
  end
end

local function open_under_cursor()
  local file = state.files[vim.api.nvim_win_get_cursor(0)[1]]
  if not file then
    return
  end
  M.leave()
  local stream = require('prflow.stream')
  local hunk = stream.first(file)
  if hunk then
    stream.jump(file, hunk)
  else
    stream.open(file)
  end
end

function M.close()
  if M.is_open() then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.buf, state.win = nil, nil
end

function M.open()
  if M.is_open() then
    return vim.api.nvim_set_current_win(state.win)
  end
  state.target = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, 'prflow://tree')
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'prflow-tree'
  vim.cmd('topleft vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_width(win, 40)
  for opt, value in pairs({
    number = false,
    relativenumber = false,
    signcolumn = 'no',
    foldcolumn = '0',
    statuscolumn = '',
    wrap = false,
    spell = false,
    list = false,
    cursorline = true,
    winfixwidth = true,
  }) do
    vim.wo[win][opt] = value
  end
  state.buf, state.win = buf, win
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, desc = desc })
  end
  map('<CR>', open_under_cursor, 'prflow: open file')
  map('<LeftRelease>', open_under_cursor, 'prflow: open file')
  map('q', M.close, 'prflow: close tree')
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      state.buf, state.win = nil, nil
    end,
  })
  M.refresh()
end

function M.toggle()
  local s = core.session
  if not (s and s.ready) then
    return vim.notify('prflow: not in review mode', vim.log.levels.WARN)
  end
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

return M
