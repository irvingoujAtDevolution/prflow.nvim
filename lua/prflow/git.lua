local M = {}

local function argv(args)
  return vim.list_extend({ 'git' }, args)
end

local function check(r, args)
  if r.code ~= 0 then
    error(('prflow: git %s failed: %s'):format(table.concat(args, ' '), vim.trim(r.stderr or '')), 0)
  end
  return r.stdout
end

-- Calls `cb(stdout)` on the main loop.
function M.run(root, args, cb)
  vim.system(argv(args), { cwd = root, text = true }, function(r)
    vim.schedule(function()
      cb(check(r, args))
    end)
  end)
end

function M.run_sync(root, args)
  return check(vim.system(argv(args), { cwd = root, text = true }):wait(), args)
end

function M.repo(cwd)
  local out = vim.split(vim.trim(M.run_sync(cwd, { 'rev-parse', '--show-toplevel', '--absolute-git-dir', '--abbrev-ref', 'HEAD' })), '\n')
  return { root = out[1], gitdir = out[2], branch = out[3] }
end

function M.to_lines(text)
  local lines = vim.split(text, '\n', { plain = true })
  if lines[#lines] == '' then
    lines[#lines] = nil
  end
  for i, l in ipairs(lines) do
    if l:sub(-1) == '\r' then
      lines[i] = l:sub(1, -2)
    end
  end
  return lines
end

function M.show(root, rev, path, cb)
  M.run(root, { 'show', rev .. ':' .. path }, function(out)
    cb(M.to_lines(out))
  end)
end

function M.show_sync(root, rev, path)
  return M.to_lines(M.run_sync(root, { 'show', rev .. ':' .. path }))
end

local function split0(out)
  local toks = vim.split(out, '\0', { plain = true })
  if toks[#toks] == '' then
    toks[#toks] = nil
  end
  return toks
end

-- Parses `git diff --name-status -M -z` into { path, old_path, status }.
function M.parse_name_status(out)
  local toks, files, i = split0(out), {}, 1
  while i <= #toks do
    local kind = toks[i]:sub(1, 1)
    if kind == 'R' or kind == 'C' then
      files[#files + 1] = { status = kind, old_path = toks[i + 1], path = toks[i + 2] }
      i = i + 3
    else
      local status = (kind == 'A' or kind == 'D') and kind or 'M'
      files[#files + 1] = { status = status, old_path = toks[i + 1], path = toks[i + 1] }
      i = i + 2
    end
  end
  return files
end

-- Parses `git diff --numstat -M -z` into path -> { added, removed }.
function M.parse_numstat(out)
  local toks, counts, i = split0(out), {}, 1
  while i <= #toks do
    local added, removed, path = toks[i]:match('^(%S+)\t(%S+)\t(.*)$')
    if path == '' then
      path = toks[i + 2]
      i = i + 3
    else
      i = i + 1
    end
    counts[path] = { added = tonumber(added) or 0, removed = tonumber(removed) or 0 }
  end
  return counts
end

M.split0 = split0

local DEFAULT_BASE_ARGS = {
  'for-each-ref',
  '--format=%(refname) %(symref)',
  'refs/remotes/origin/HEAD',
  'refs/remotes/origin/main',
  'refs/remotes/origin/master',
}

-- The branch origin/HEAD points at, else origin/main, else origin/master.
function M.parse_default_base(out)
  local refs = {}
  for line in out:gmatch('[^\n]+') do
    local name, target = line:match('^(%S+) ?(%S*)$')
    refs[name] = target
  end
  local head = refs['refs/remotes/origin/HEAD']
  if head and head ~= '' then
    return (head:gsub('^refs/remotes/', ''))
  end
  if refs['refs/remotes/origin/main'] then
    return 'origin/main'
  end
  if refs['refs/remotes/origin/master'] then
    return 'origin/master'
  end
end

function M.default_base(root, cb)
  M.run(root, DEFAULT_BASE_ARGS, function(out)
    cb(M.parse_default_base(out))
  end)
end

function M.default_base_sync(root)
  return M.parse_default_base(M.run_sync(root, DEFAULT_BASE_ARGS))
end

return M
