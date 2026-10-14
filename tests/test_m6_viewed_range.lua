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

local function viewed_tops()
  return child.lua_get([[(function()
    local core = require('prflow.core')
    local out = {}
    for _, h in ipairs(require('prflow').hunks('A')) do
      if core.is_viewed(h) then table.insert(out, h.top) end
    end
    return out
  end)()]])
end

local function where()
  return child.lua_get([[vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t') .. ':' .. vim.api.nvim_win_get_cursor(0)[1] ]])
end

T['viewed'] = MiniTest.new_set()

T['viewed']['toggle marks the hunk under the cursor and dims it'] = function()
  child.cmd('10')
  child.type_keys([[\hv]])
  eq(viewed_tops(), { 10 })
  local hl = child.lua_get([[(function()
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, require('prflow.render').ns, { 9, 0 }, { 9, -1 }, { details = true })) do
      if m[4].virt_lines then return m[4].virt_lines[1][1][2] end
    end
  end)()]])
  eq(hl, 'PrflowViewed')
  child.type_keys([[\hv]])
  eq(viewed_tops(), {})
end

T['viewed'][']h skips viewed hunks unless show_viewed'] = function()
  child.cmd('10')
  child.type_keys([[\hv]])
  child.cmd('1')
  child.type_keys(']h')
  eq(where(), 'A:3')
  child.type_keys(']h')
  eq(where(), 'A:19')
  child.lua([[vim.g.prflow = { show_viewed = true }]])
  child.cmd('3')
  child.type_keys(']h')
  eq(where(), 'A:10')
end

T['viewed']['state survives stop and restart'] = function()
  child.cmd('3')
  child.type_keys([[\hv]])
  child.cmd('PrflowStop')
  H.start(child)
  eq(viewed_tops(), { 3 })
  local gitdir = vim.trim(fixture.git(fx.root, 'rev-parse', '--absolute-git-dir'))
  local data = vim.json.decode(table.concat(vim.fn.readfile(gitdir .. '/prflow/state.json'), '\n'))
  eq(vim.tbl_count(data.branches.feature.viewed), 1)
end

T['viewed']['editing a viewed hunk unviews it'] = function()
  child.cmd('3')
  child.type_keys([[\hv]])
  eq(viewed_tops(), { 3 })
  child.type_keys('A', '!', '<Esc>')
  H.wait(child, "require('prflow').hunks('A')[1].new_lines[1] == 'line three!'")
  eq(viewed_tops(), {})
end

T['range'] = MiniTest.new_set()

T['range']['since-review shows only changes after the recorded HEAD'] = function()
  child.cmd('PrflowMarkReviewed')
  fixture.write(fx.root, 'D', { 'd1', 'd2 changed' })
  fixture.git(fx.root, 'add', 'D')
  fixture.git(fx.root, 'commit', '-q', '-m', 'after review')
  child.cmd('PrflowRange since-review')
  H.wait(child, "require('prflow').status().ready")
  eq(child.lua_get([[require('prflow').status().mode]]), 'since-review')
  eq(H.files(child), { { 'D', 'M' }, { 'E', 'M' }, { 'G', 'A' } })
  child.cmd('PrflowRange base')
  H.wait(child, "require('prflow').status().ready")
  eq(#H.files(child), 7)
end

T['range']['commit <sha> diffs against that commit'] = function()
  local head = vim.trim(fixture.git(fx.root, 'rev-parse', 'HEAD'))
  child.cmd('PrflowRange commit ' .. head)
  H.wait(child, "require('prflow').status().ready")
  eq(H.files(child), { { 'E', 'M' }, { 'G', 'A' } })
  eq(child.lua_get([[require('prflow').status().base]]), head)
end

return T
