-- Builds a throwaway repo pair (bare origin + work clone) for tests.
local F = {}

function F.git(cwd, ...)
  local r = vim.system({ 'git', ... }, { cwd = cwd, text = true }):wait()
  if r.code ~= 0 then
    error(('git %s failed: %s'):format(table.concat({ ... }, ' '), r.stderr), 2)
  end
  return r.stdout
end

function F.write(dir, path, lines)
  local full = dir .. '/' .. path
  vim.fn.mkdir(vim.fs.dirname(full), 'p')
  local f = assert(io.open(full, 'wb'))
  f:write(table.concat(lines, '\n') .. '\n')
  f:close()
end

function F.seq(prefix, n)
  local t = {}
  for i = 1, n do
    t[i] = prefix .. i
  end
  return t
end

local function init_repo(dir)
  F.git(dir, 'init', '-q', '-b', 'main')
  F.git(dir, 'config', 'user.name', 'prflow test')
  F.git(dir, 'config', 'user.email', 'test@example.com')
  F.git(dir, 'config', 'core.autocrlf', 'false')
  F.git(dir, 'config', 'commit.gpgsign', 'false')
  F.git(dir, 'config', 'core.hooksPath', '.no-hooks')
end

function F.commit(dir, msg)
  F.git(dir, 'add', '-A')
  F.git(dir, 'commit', '-q', '-m', msg)
end

-- Creates an origin + work repo. `main` has `base_files`; `feature` is
-- checked out with `edit(dir)` applied and committed. Returns the paths.
function F.make(base_files, edit)
  local tmp = vim.fs.normalize(vim.fn.tempname())
  local origin, work = tmp .. '/origin.git', tmp .. '/work'
  vim.fn.mkdir(origin, 'p')
  vim.fn.mkdir(work, 'p')
  F.git(origin, 'init', '-q', '--bare', '-b', 'main')
  init_repo(work)
  for path, lines in pairs(base_files) do
    F.write(work, path, lines)
  end
  F.commit(work, 'base')
  F.git(work, 'remote', 'add', 'origin', origin)
  F.git(work, 'push', '-q', '-u', 'origin', 'main')
  F.git(work, 'checkout', '-q', '-b', 'feature')
  if edit then
    edit(work)
  end
  return { tmp = tmp, root = work, origin = origin }
end

-- The standard fixture from the spec:
-- A modified (4 hunks), F added, B deleted, C -> C2 renamed with an edit,
-- D unchanged, E with an uncommitted edit, G untracked.
function F.standard()
  local base = {
    A = F.seq('line ', 30),
    B = F.seq('b', 4),
    C = F.seq('c line ', 10),
    D = { 'd1', 'd2' },
    E = F.seq('e', 5),
  }
  return F.make(base, function(dir)
    local a = F.seq('line ', 30)
    a[3] = 'line three'
    a[28] = 'line 28 // edited'
    table.insert(a, 21, 'new 2')
    table.insert(a, 21, 'new 1')
    table.remove(a, 11)
    table.remove(a, 10)
    F.write(dir, 'A', a)
    F.write(dir, 'F', { 'f1', 'f2', 'f3' })
    F.git(dir, 'rm', '-q', 'B')
    F.git(dir, 'mv', 'C', 'C2')
    local c = F.seq('c line ', 10)
    c[5] = 'c line five'
    F.write(dir, 'C2', c)
    F.commit(dir, 'feature work')
    F.write(dir, 'E', { 'e1', 'e2', 'e three', 'e4', 'e5' })
    F.write(dir, 'G', { 'g1', 'g2' })
  end)
end

function F.cleanup(fx)
  if fx then
    vim.fn.delete(fx.tmp, 'rf')
  end
end

return F
