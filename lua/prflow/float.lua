-- Side-by-side view of one hunk: base on the left, current on the right.
local stream = require('prflow.stream')

local M = {}

local open = nil

local function scratch(lines, ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  if ft ~= '' then
    vim.bo[buf].filetype = ft
  end
  return buf
end

function M.close()
  if not open then
    return
  end
  local o = open
  open = nil
  vim.api.nvim_del_augroup_by_id(o.group)
  for _, win in ipairs(o.wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  for _, buf in ipairs(o.bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  if vim.api.nvim_win_is_valid(o.origin) then
    vim.api.nvim_set_current_win(o.origin)
  end
end

function M.open()
  M.close()
  local file, h = stream.hunk_at_cursor()
  if not h then
    return vim.notify('prflow: no hunk under cursor', vim.log.levels.WARN)
  end
  local ft = vim.bo.filetype
  local origin = vim.api.nvim_get_current_win()
  local width = math.max(20, math.floor((vim.o.columns - 6) / 2))
  local height = math.max(1, math.min(math.max(#h.old_lines, #h.new_lines), vim.o.lines - 6))
  local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
  local col = math.max(0, math.floor((vim.o.columns - 2 * width - 4) / 2))
  local sides = {
    { h.old_lines, ' base: ' .. file.old_path .. ' ' },
    { h.new_lines, ' current: ' .. file.path .. ' ' },
  }
  local o = { wins = {}, bufs = {}, origin = origin, group = vim.api.nvim_create_augroup('prflow_float', { clear = true }) }
  open = o
  for i, side in ipairs(sides) do
    local buf = scratch(side[1], ft)
    local win = vim.api.nvim_open_win(buf, i == 2, {
      relative = 'editor',
      row = row,
      col = col + (i - 1) * (width + 2),
      width = width,
      height = height,
      border = 'rounded',
      title = side[2],
      style = 'minimal',
    })
    vim.api.nvim_win_call(win, function()
      vim.cmd('diffthis')
    end)
    vim.wo[win].foldenable = false
    vim.keymap.set('n', 'q', M.close, { buffer = buf, nowait = true, desc = 'prflow: close hunk view' })
    vim.keymap.set('n', '<CR>', function()
      local line = h.top
      if i == 2 and h.new_count > 0 then
        line = h.new_start + vim.api.nvim_win_get_cursor(0)[1] - 1
      end
      M.close()
      local last = vim.api.nvim_buf_line_count(0)
      vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(line, last)), 0 })
    end, { buffer = buf, nowait = true, desc = 'prflow: jump to this line in the file' })
    o.bufs[i], o.wins[i] = buf, win
  end
  vim.api.nvim_create_autocmd('WinClosed', {
    group = o.group,
    callback = function(ev)
      if vim.tbl_contains(o.wins, tonumber(ev.match)) then
        vim.schedule(M.close)
      end
    end,
  })
end

return M
