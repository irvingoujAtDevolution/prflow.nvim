local fixture = require('tests.helpers.fixture')
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()
local fx

T['fixture'] = MiniTest.new_set({
  hooks = {
    pre_case = function() fx = fixture.standard() end,
    post_case = function() fixture.cleanup(fx) end,
  },
})

T['fixture']['builds the feature branch with uncommitted and untracked changes'] = function()
  eq(vim.trim(fixture.git(fx.root, 'rev-parse', '--abbrev-ref', 'HEAD')), 'feature')
  local status = fixture.git(fx.root, 'status', '--porcelain')
  eq(status, ' M E\n?? G\n')
  eq(vim.fn.filereadable(fx.root .. '/D'), 1)
end

return T
