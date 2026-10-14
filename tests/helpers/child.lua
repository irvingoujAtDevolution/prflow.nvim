-- Child Neovim helpers shared by the specs.
local H = {}

function H.new()
  return MiniTest.new_child_neovim()
end

function H.boot(child, root)
  child.restart({ '-u', 'tests/minimal_init.lua' })
  child.lua('vim.cmd.cd(...)', { root })
end

function H.wait(child, expr, timeout)
  local ok = child.lua_get(('vim.wait(%d, function() return %s end, 10)'):format(timeout or 5000, expr))
  if not ok then
    error('timed out waiting for: ' .. expr, 2)
  end
end

function H.start(child, args)
  child.cmd('PrflowStart' .. (args and (' ' .. args) or ''))
  H.wait(child, "require('prflow').status().ready")
end

-- Hunk ranges for `path` as { old_start, old_count, new_start, new_count }.
function H.ranges(child, path)
  return child.lua_get(
    [[vim.tbl_map(function(h) return { h.old_start, h.old_count, h.new_start, h.new_count } end, require('prflow').hunks(...))]],
    { path }
  )
end

function H.files(child)
  return child.lua_get([[vim.tbl_map(function(f) return { f.path, f.status } end, require('prflow').status().files)]])
end

return H
