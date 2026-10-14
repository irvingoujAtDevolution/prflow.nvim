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
        _G.select_choice = nil
        vim.ui.select = function(items, opts, on_choice)
          _G.shown = vim.tbl_map(opts.format_item, items)
          for _, it in ipairs(items) do
            if opts.format_item(it):find(_G.select_choice or '\0', 1, true) then return on_choice(it) end
          end
          on_choice(nil)
        end
      ]])
      H.start(child)
    end,
    post_case = function()
      child.stop()
      fixture.cleanup(fx)
    end,
  },
})

-- Expected `<status> <path> +x -y` lines, counts straight from git.
local function expected()
  local base = vim.trim(fixture.git(fx.root, 'merge-base', 'origin/main', 'HEAD'))
  local counts = {}
  for _, line in ipairs(vim.split(vim.trim(fixture.git(fx.root, 'diff', '--numstat', '-M', base)), '\n')) do
    local a, d, path = line:match('^(%d+)\t(%d+)\t(.*)$')
    counts[path:match('=> (.*)$') or path] = { a, d }
  end
  counts.G = { '2', '0' }
  local out = {}
  for _, f in ipairs({ { 'M', 'A' }, { 'D', 'B' }, { 'R', 'C2' }, { 'M', 'E' }, { 'A', 'F' }, { 'A', 'G' } }) do
    local c = counts[f[2]]
    out[#out + 1] = ('%s %s +%s -%s'):format(f[1], f[2], c[1], c[2])
  end
  return out
end

T['lists changed files with git numstat counts'] = function()
  child.cmd('PrflowFiles')
  eq(child.lua_get('_G.shown'), expected())
end

T['counts stay right after a file is loaded'] = function()
  child.cmd('edit A')
  H.wait(child, "require('prflow.core').session.by_path.A.hunks ~= nil")
  child.cmd('PrflowFiles')
  eq(child.lua_get('_G.shown'), expected())
end

T['selecting a file opens it at its first hunk'] = function()
  child.lua([[_G.select_choice = ' C2 ']])
  child.cmd('PrflowFiles')
  eq(child.lua_get([[vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t')]]), 'C2')
  eq(child.lua_get('vim.api.nvim_win_get_cursor(0)[1]'), 5)
end

return T
