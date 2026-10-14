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
    end,
    post_case = function()
      child.stop()
      fixture.cleanup(fx)
    end,
  },
})

local A_HUNKS = { { 3, 1, 3, 1 }, { 10, 2, 9, 0 }, { 20, 0, 19, 2 }, { 28, 1, 28, 1 } }

T['lists exactly the changed files with statuses'] = function()
  H.start(child)
  eq(H.files(child), { { 'A', 'M' }, { 'B', 'D' }, { 'C2', 'R' }, { 'E', 'M' }, { 'F', 'A' }, { 'G', 'A' } })
  eq(child.lua_get([[require('prflow').status().files[3].old_path]]), 'C')
end

T['computes hunks for A'] = function()
  H.start(child)
  child.cmd('edit A')
  eq(H.ranges(child, 'A'), A_HUNKS)
end

T['recomputes hunks after debounce without calling git'] = function()
  H.start(child)
  child.cmd('edit A')
  H.wait(child, "require('prflow.core').session.by_path.A.base_lines ~= nil")
  eq(H.ranges(child, 'A'), A_HUNKS)
  child.lua([[
    _G.git_calls = 0
    vim.system = function() _G.git_calls = _G.git_calls + 1; error('git must not run') end
  ]])
  child.type_keys('gg', 'O', 'inserted', '<Esc>')
  eq(H.ranges(child, 'A'), A_HUNKS)
  H.wait(child, "require('prflow').hunks('A')[1].new_start == 1")
  eq(H.ranges(child, 'A'), { { 0, 0, 1, 1 }, { 3, 1, 4, 1 }, { 10, 2, 10, 0 }, { 20, 0, 20, 2 }, { 28, 1, 29, 1 } })
  eq(child.lua_get('_G.git_calls'), 0)
end

T['start accepts an explicit ref'] = function()
  H.start(child, 'main')
  eq(#H.files(child), 6)
end

T['status and stop'] = function()
  eq(child.lua_get([[require('prflow').status().active]]), false)
  H.start(child)
  local msg = child.cmd_capture('PrflowStatus')
  MiniTest.expect.no_equality(msg:find('feature vs origin/main', 1, true), nil)
  MiniTest.expect.no_equality(msg:find('6 files', 1, true), nil)
  child.cmd('PrflowStop')
  eq(child.lua_get([[require('prflow').status().active]]), false)
  eq(child.cmd_capture('PrflowStatus'), 'prflow: inactive')
end

return T
