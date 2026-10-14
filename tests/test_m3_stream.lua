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
      child.lua([[
        _G.notes = {}
        vim.notify = function(msg) table.insert(_G.notes, msg) end
      ]])
      H.start(child)
      child.cmd('edit A')
    end,
    post_case = function()
      child.stop()
      fixture.cleanup(fx)
    end,
  },
})

local function where()
  return child.lua_get([[(function()
    local name = vim.api.nvim_buf_get_name(0)
    if not name:match('^prflow://') then name = vim.fn.fnamemodify(name, ':t') end
    return name .. ':' .. vim.api.nvim_win_get_cursor(0)[1]
  end)()]])
end

local ORDER = { 'A:3', 'A:10', 'A:19', 'A:28', 'prflow://deleted/B:1', 'C2:5', 'E:3', 'F:1', 'G:1' }

T[']h visits every hunk of every file once, in order, then wraps'] = function()
  local seen = {}
  for _ = 1, #ORDER do
    child.type_keys(']h')
    table.insert(seen, where())
  end
  eq(seen, ORDER)
  eq(child.lua_get('#_G.notes'), 0)
  child.type_keys(']h')
  eq(where(), 'A:3')
  eq(child.lua_get('_G.notes'), { 'prflow: wrapped to first hunk' })
end

T['[h walks the stream backwards and wraps'] = function()
  child.type_keys('[h')
  eq(where(), 'G:1')
  eq(child.lua_get('_G.notes'), { 'prflow: wrapped to last hunk' })
  local seen = {}
  for _ = 1, #ORDER - 1 do
    child.type_keys('[h')
    table.insert(seen, where())
  end
  eq(seen, vim.list_slice(vim.fn.reverse(vim.deepcopy(ORDER)), 2))
end

T['deleted file opens as a readonly scratch buffer, all lines deleted'] = function()
  child.lua([[require('prflow.stream').open(require('prflow.core').session.by_path.B)]])
  eq(where(), 'prflow://deleted/B:1')
  eq(child.lua_get('vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'b1', 'b2', 'b3', 'b4' })
  eq(child.lua_get('{ vim.bo.readonly, vim.bo.modifiable, vim.bo.buftype }'), { true, false, 'nofile' })
  local hl = child.lua_get([[vim.tbl_map(function(m) return m[4].line_hl_group end,
    vim.api.nvim_buf_get_extmarks(0, require('prflow.render').ns, 0, -1, { details = true }))]])
  eq(hl, { 'PrflowDelete', 'PrflowDelete', 'PrflowDelete', 'PrflowDelete' })
  child.cmd('PrflowStop')
  eq(child.lua_get([[vim.fn.bufexists('prflow://deleted/B')]]), 0)
end

T['keymaps are configurable and restored on stop'] = function()
  child.cmd('PrflowStop')
  child.lua([[vim.keymap.set('n', ']h', '<Cmd>let g:user_map = 1<CR>')]])
  child.lua([[vim.g.prflow = { keys = { next = 'gn' } }]])
  H.start(child)
  child.type_keys('gn')
  eq(where(), 'A:3')
  child.cmd('PrflowStop')
  child.type_keys(']h')
  eq(child.lua_get('vim.g.user_map'), 1)
  eq(child.lua_get([[vim.fn.maparg('gn', 'n')]]), '')
end

return T
