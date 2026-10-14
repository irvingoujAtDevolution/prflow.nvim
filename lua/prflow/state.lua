-- Persistent review state in <git-dir>/prflow/state.json, keyed by branch.
local M = {}

local function file(gitdir)
  return gitdir .. '/prflow/state.json'
end

function M.load(gitdir)
  local f = io.open(file(gitdir), 'r')
  if not f then
    return { branches = {} }
  end
  local data = vim.json.decode(f:read('*a'))
  f:close()
  data.branches = data.branches or {}
  return data
end

function M.save(gitdir, data)
  vim.fn.mkdir(gitdir .. '/prflow', 'p')
  local f = assert(io.open(file(gitdir), 'w'))
  f:write(vim.json.encode(data))
  f:close()
end

function M.branch(data, name)
  local b = data.branches[name] or {}
  b.viewed = b.viewed or vim.empty_dict()
  data.branches[name] = b
  return b
end

return M
