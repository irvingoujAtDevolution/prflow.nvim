local fixture = require('tests.helpers.fixture')
local H = require('tests.helpers.child')
local eq = MiniTest.expect.equality

local child = H.new()
local fx

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      fx = fixture.standard()
      H.boot(child, fx.root)
      H.start(child)
      child.cmd('edit A')
      H.wait(child, "#vim.api.nvim_buf_get_extmarks(0, require('prflow.render').ns, 0, -1, {}) > 0")
    end,
    post_case = function()
      child.stop()
      fixture.cleanup(fx)
    end,
  },
})

T['word diff'] = MiniTest.new_set()

T['word diff']['ranges for known edits'] = function()
  eq(child.lua_get([[{ require('prflow.diff').words('line 3', 'line three') }]]), { { { 5, 6 } }, { { 5, 10 } } })
  eq(child.lua_get([[{ require('prflow.diff').words('line 28', 'line 28 // edited') }]]), { {}, { { 7, 17 } } })
  eq(child.lua_get([[{ require('prflow.diff').words('a b c', 'a x c') }]]), { { { 2, 3 } }, { { 2, 3 } } })
end

T['word diff']['highlights changed words in the buffer and in deleted lines'] = function()
  local marks = child.lua_get([[(function()
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, require('prflow.render').ns, 0, -1, { details = true })) do
      if m[4].hl_group == 'PrflowAddText' then table.insert(out, { m[2], m[3], m[4].end_col }) end
    end
    return out
  end)()]])
  eq(marks, { { 2, 5, 10 }, { 27, 7, 17 } })
  local old_words = child.lua_get([[(function()
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, require('prflow.render').ns, 0, -1, { details = true })) do
      for _, vl in ipairs(m[4].virt_lines or {}) do
        for _, chunk in ipairs(vl) do
          if chunk[2] == 'PrflowDeleteText' then table.insert(out, { m[2], chunk[1] }) end
        end
      end
    end
    return out
  end)()]])
  eq(old_words, { { 2, '3' } })
end

T['float'] = MiniTest.new_set()

local function snapshot()
  return child.lua_get('{ wins = vim.api.nvim_list_wins(), bufs = vim.api.nvim_list_bufs() }')
end

T['float']['opens old and new side by side in diff mode, q closes both'] = function()
  local before = snapshot()
  child.cmd('3')
  child.cmd('PrflowHunk')
  local wins = child.lua_get([[vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative ~= '' end, vim.api.nvim_list_wins())]])
  eq(#wins, 2)
  local info = child.lua_get([[vim.tbl_map(function(w)
    return { lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false), diff = vim.wo[w].diff, col = vim.api.nvim_win_get_position(w)[2] }
  end, ...)]], { wins })
  table.sort(info, function(a, b) return a.col < b.col end)
  eq({ info[1].lines, info[1].diff }, { { 'line 3' }, true })
  eq({ info[2].lines, info[2].diff }, { { 'line three' }, true })
  child.type_keys('q')
  eq(snapshot(), before)
end

T['float']['leader mapping opens it and closing one float closes the other'] = function()
  local before = snapshot()
  child.cmd('19')
  child.type_keys([[\hd]])
  eq(#child.lua_get('vim.api.nvim_list_wins()'), 3)
  eq(child.lua_get('vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'new 1', 'new 2' })
  child.cmd('close')
  H.wait(child, '#vim.api.nvim_list_wins() == 1')
  eq(snapshot(), before)
end

return T
