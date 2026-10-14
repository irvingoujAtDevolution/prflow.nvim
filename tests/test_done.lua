-- Definition-of-done checks: health, worktrees, performance.
local fixture = require('tests.helpers.fixture')
local H = require('tests.helpers.child')
local eq = MiniTest.expect.equality

local child = H.new()
local fx

local T = MiniTest.new_set({
  hooks = {
    post_case = function()
      child.stop()
      fixture.cleanup(fx)
    end,
  },
})

local function health_text()
  child.cmd('checkhealth prflow')
  return table.concat(child.lua_get('vim.api.nvim_buf_get_lines(0, 0, -1, false)'), '\n')
end

T['checkhealth reports no errors in a valid repo'] = function()
  fx = fixture.standard()
  H.boot(child, fx.root)
  local text = health_text()
  eq(text:find('ERROR', 1, true), nil)
  MiniTest.expect.no_equality(text:find('Base ref origin/main exists', 1, true), nil)
end

T['checkhealth reports a missing base ref'] = function()
  fx = fixture.standard()
  H.boot(child, fx.root)
  child.lua([[vim.g.prflow = { base = 'origin/nope' }]])
  MiniTest.expect.no_equality(health_text():find('ERROR', 1, true), nil)
end

T['works in a git worktree and keeps state in its git-dir'] = function()
  fx = fixture.standard()
  local wt = fx.tmp .. '/wt'
  fixture.git(fx.root, 'worktree', 'add', '-q', '-b', 'wt-review', wt, 'feature')
  H.boot(child, wt)
  H.start(child)
  eq(H.files(child), { { 'A', 'M' }, { 'B', 'D' }, { 'C2', 'R' }, { 'F', 'A' } })
  child.cmd('edit A')
  child.cmd('3')
  child.lua([[require('prflow').toggle_viewed()]])
  local gitdir = vim.trim(fixture.git(wt, 'rev-parse', '--absolute-git-dir'))
  eq(vim.fn.filereadable(gitdir .. '/prflow/state.json'), 1)
  eq(vim.fn.filereadable(fx.root .. '/.git/prflow/state.json'), 0)
end

local function big_fixture()
  local base = { big = fixture.seq('big line ', 5000) }
  for i = 1, 200 do
    base[('src/f%03d.txt'):format(i)] = { 'one', 'two', 'three' }
  end
  return fixture.make(base, function(dir)
    for i = 1, 200 do
      fixture.write(dir, ('src/f%03d.txt'):format(i), { 'one', 'TWO', 'three' })
    end
    local big = fixture.seq('big line ', 5000)
    big[2500] = 'big line changed'
    fixture.write(dir, 'big', big)
    fixture.commit(dir, 'touch everything')
  end)
end

T['performance: start returns fast, keystrokes wait for the debounce'] = function()
  fx = big_fixture()
  H.boot(child, fx.root)
  local start_ms = child.lua_get([[(function()
    local t = vim.uv.hrtime()
    vim.cmd('PrflowStart')
    return (vim.uv.hrtime() - t) / 1e6
  end)()]])
  local ready_ms = child.lua_get([[(function()
    local t = vim.uv.hrtime()
    vim.wait(10000, function() return require('prflow').status().ready end, 1)
    return (vim.uv.hrtime() - t) / 1e6
  end)()]])
  eq(#H.files(child), 201)
  child.cmd('edit big')
  H.wait(child, "require('prflow.core').session.by_path.big.hunks ~= nil")
  child.lua([[
    local diff = require('prflow.diff')
    local orig = diff.hunks
    _G.recomputes, _G.recompute_ms = 0, 0
    diff.hunks = function(...)
      local t = vim.uv.hrtime()
      local out = orig(...)
      _G.recompute_ms = (vim.uv.hrtime() - t) / 1e6
      _G.recomputes = _G.recomputes + 1
      return out
    end
  ]])
  child.cmd('2500')
  child.type_keys('A', 'x')
  eq(child.lua_get('_G.recomputes'), 0)
  child.lua('vim.wait(100, function() return false end)')
  eq(child.lua_get('_G.recomputes'), 0)
  H.wait(child, '_G.recomputes > 0')
  child.type_keys('<Esc>')
  MiniTest.add_note(('start=%.1fms ready=%.1fms recompute(5000 lines)=%.1fms'):format(
    start_ms, ready_ms, child.lua_get('_G.recompute_ms')))
  eq(start_ms < 200, true)
end

return T
