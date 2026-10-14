local fixture = require('tests.helpers.fixture')
local H = require('tests.helpers.child')
local eq = MiniTest.expect.equality

local child = H.new()
local fx

local INIT = vim.fs.normalize(vim.fn.getcwd()) .. '/tests/minimal_init.lua'

-- Boots a child with auto mode on (the default), starting inside `dir`.
local function boot_auto(dir)
  child.restart({ '--cmd', 'lua vim.g.prflow = {}', '--cmd', 'cd ' .. dir, '-u', INIT })
end

local function prflow_messages()
  return child.lua_get([[vim.tbl_filter(function(l) return l:find('prflow') or l:find('E%d+:') end, vim.split(vim.fn.execute('messages'), '\n'))]])
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      fx = fixture.standard()
    end,
    post_case = function()
      child.stop()
      fixture.cleanup(fx)
    end,
  },
})

T['starts by itself in a git repo, no command needed'] = function()
  boot_auto(fx.root)
  H.wait(child, "require('prflow').status().ready")
  eq(#H.files(child), 6)
  child.cmd('edit A')
  H.wait(child, "#vim.api.nvim_buf_get_extmarks(0, require('prflow.render').ns, 0, -1, {}) > 0")
  child.type_keys(']h')
  eq(child.lua_get('vim.api.nvim_win_get_cursor(0)[1]'), 3)
end

T['stays silent outside a git repo and starts after :cd into one'] = function()
  local plain = fx.tmp .. '/plain'
  vim.fn.mkdir(plain, 'p')
  boot_auto(plain)
  H.wait(child, "vim.fn.exists('#prflow_auto#DirChanged') == 1")
  child.lua('vim.wait(800, function() return false end)')
  eq(child.lua_get([[require('prflow').status().active]]), false)
  eq(prflow_messages(), {})
  child.cmd('cd ' .. fx.root)
  H.wait(child, "require('prflow').status().ready")
  eq(#H.files(child), 6)
end

T['stays silent when the repo has no base ref'] = function()
  fixture.git(fx.root, 'remote', 'remove', 'origin')
  boot_auto(fx.root)
  H.wait(child, "vim.fn.exists('#prflow_auto#DirChanged') == 1")
  child.lua('vim.wait(800, function() return false end)')
  eq(child.lua_get([[require('prflow').status().active]]), false)
  eq(child.lua_get([[vim.fn.maparg(']h', 'n')]]), '')
  eq(prflow_messages(), {})
end

T['reloads when HEAD moves or the branch changes'] = function()
  boot_auto(fx.root)
  H.wait(child, "require('prflow').status().ready")
  fixture.write(fx.root, 'D', { 'd1', 'd2 changed' })
  fixture.git(fx.root, 'add', 'D')
  fixture.git(fx.root, 'commit', '-q', '-m', 'touch D')
  child.lua('vim.wait(1100, function() return false end)')
  child.cmd('edit A')
  H.wait(child, "require('prflow').status().ready and #require('prflow').status().files == 7")
  fixture.git(fx.root, 'checkout', '-q', '-b', 'other')
  child.lua('vim.wait(1100, function() return false end)')
  child.cmd('doautocmd FocusGained')
  H.wait(child, "require('prflow').status().branch == 'other'")
end

T[':PrflowStop stays stopped'] = function()
  boot_auto(fx.root)
  H.wait(child, "require('prflow').status().ready")
  child.cmd('PrflowStop')
  child.lua('vim.wait(1100, function() return false end)')
  child.cmd('edit A')
  child.cmd('doautocmd FocusGained')
  child.lua('vim.wait(300, function() return false end)')
  eq(child.lua_get([[require('prflow').status().active]]), false)
end

T['auto = false leaves it manual'] = function()
  child.restart({ '--cmd', 'lua vim.g.prflow = { auto = false }', '--cmd', 'cd ' .. fx.root, '-u', INIT })
  child.lua('vim.wait(800, function() return false end)')
  eq(child.lua_get([[require('prflow').status().active]]), false)
  eq(child.lua_get([[vim.fn.exists('#prflow_auto')]]), 0)
end

return T
