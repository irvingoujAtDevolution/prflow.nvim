local fixture = require('tests.helpers.fixture')
local H = require('tests.helpers.child')
local eq = MiniTest.expect.equality

local child = H.new()
local fx

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      fx = fixture.standard()
      fixture.write(fx.root, 'src/deep/x.txt', { 'x1' })
      fixture.write(fx.root, 'src/y.txt', { 'y1', 'y2' })
      H.boot(child, fx.root)
      child.lua([[vim.notify = function() end]])
      H.start(child)
      child.cmd('edit A')
      H.wait(child, "require('prflow.core').session.by_path.A.hunks ~= nil")
    end,
    post_case = function()
      child.stop()
      fixture.cleanup(fx)
    end,
  },
})

local function tree_lines()
  return child.lua_get([[(function()
    local t = require('prflow.tree')
    return vim.tbl_map(function(l) return (l:gsub('%s+$', '')) end, vim.api.nvim_buf_get_lines(t.buf(), 0, -1, false))
  end)()]])
end

local function line_of(pattern)
  for i, l in ipairs(tree_lines()) do
    if l:match(pattern) then
      return i
    end
  end
  error('no tree line matches ' .. pattern)
end

local function where()
  return child.lua_get([[(function()
    local name = vim.api.nvim_buf_get_name(0)
    if not name:match('^prflow://') then name = vim.fn.fnamemodify(name, ':.') end
    return name .. ':' .. vim.api.nvim_win_get_cursor(0)[1]
  end)()]])
end

local function is_tree_win()
  return child.lua_get([[vim.api.nvim_get_current_win() == require('prflow.tree').win()]])
end

T['opens a left sidebar listing files by directory, in stream order'] = function()
  local main = child.lua_get('vim.api.nvim_get_current_win()')
  child.cmd('PrflowTree')
  eq(is_tree_win(), true)
  eq(child.lua_get('vim.api.nvim_win_get_position(0)[2]'), 0)
  eq(child.lua_get('#vim.api.nvim_tabpage_list_wins(0)'), 2)
  local lines = tree_lines()
  eq(lines[1], 'feature vs origin/main')
  local shape = vim.tbl_map(function(l) return (l:gsub('%s+[%+%-].*$', '')) end, vim.list_slice(lines, 2))
  eq(shape, { 'M A', 'D B', 'R C2', 'M E', 'A F', 'A G', 'src/', '  deep/', '    A x.txt', '  A y.txt' })
  MiniTest.expect.no_equality(child.lua_get('vim.api.nvim_win_is_valid(...)', { main }), false)
end

T['shows counts and viewed progress for computed files only'] = function()
  child.cmd('PrflowTree')
  eq(tree_lines()[line_of('^M A')]:match('%+4 %-4%s+0/4$') ~= nil, true)
  eq(tree_lines()[line_of('^D B')]:match('%+0 %-4%s+%?$') ~= nil, true)
  child.cmd('wincmd p')
  child.cmd('3')
  child.lua([[require('prflow').toggle_viewed()]])
  eq(tree_lines()[line_of('^M A')]:match('1/4$') ~= nil, true)
end

T['<CR> opens the file in the main window at its first hunk'] = function()
  child.cmd('PrflowTree')
  child.cmd(tostring(line_of('^R C2')))
  child.type_keys('<CR>')
  eq(is_tree_win(), false)
  eq(where(), 'C2:5')
  eq(child.lua_get('#vim.api.nvim_tabpage_list_wins(0)'), 2)
end

T['a single mouse click opens the file'] = function()
  child.cmd('PrflowTree')
  local row = line_of('^M E') - 1
  child.api.nvim_input_mouse('left', 'press', '', 0, row, 3)
  child.api.nvim_input_mouse('left', 'release', '', 0, row, 3)
  H.wait(child, "vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t') == 'E'")
  eq(where(), 'E:3')
end

T['next hunk from inside the tree jumps in the main window'] = function()
  child.cmd('PrflowTree')
  child.type_keys(']h')
  eq(is_tree_win(), false)
  eq(where(), 'A:3')
  eq(child.lua_get('#vim.api.nvim_tabpage_list_wins(0)'), 2)
end

T['highlights the current file and follows navigation'] = function()
  child.cmd('PrflowTree')
  child.cmd('wincmd p')
  local function current_line()
    return child.lua_get([[(function()
      local t = require('prflow.tree')
      local m = vim.api.nvim_buf_get_extmarks(t.buf(), t.ns, 0, -1, { details = true })
      for _, x in ipairs(m) do
        if x[4].line_hl_group == 'PrflowTreeCurrent' then return x[2] + 1 end
      end
    end)()]])
  end
  eq(current_line(), line_of('^M A'))
  child.cmd('normal! G')
  child.type_keys(']h')
  eq(where(), 'prflow://deleted/B:1')
  eq(current_line(), line_of('^D B'))
end

T['toggle closes it and stop closes it'] = function()
  child.cmd('PrflowTree')
  child.cmd('PrflowTree')
  eq(child.lua_get('#vim.api.nvim_tabpage_list_wins(0)'), 1)
  child.cmd('PrflowTree')
  child.cmd('PrflowStop')
  eq(child.lua_get('#vim.api.nvim_tabpage_list_wins(0)'), 1)
  eq(child.lua_get([[vim.fn.bufexists('prflow://tree')]]), 0)
end

T['<CR> in the hunk float jumps to that line in the real file'] = function()
  child.cmd('19')
  child.cmd('PrflowHunk')
  child.type_keys('j', '<CR>')
  eq(child.lua_get('#vim.api.nvim_list_wins()'), 1)
  eq(where(), 'A:20')
end

return T
