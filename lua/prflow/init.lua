local M = {}

local function core()
  return require('prflow.core')
end

function M.setup(opts)
  vim.g.prflow = vim.tbl_deep_extend('force', vim.g.prflow or {}, opts or {})
end

function M.start(ref)
  core().start(ref)
end

function M.stop()
  core().stop()
end

function M.status()
  local s = core().session
  if not s then
    return { active = false }
  end
  return {
    active = true,
    ready = s.ready,
    branch = s.branch,
    ref = s.ref,
    base = s.base,
    mode = s.range.mode,
    files = vim.tbl_map(function(f)
      return { path = f.path, old_path = f.old_path, status = f.status, added = f.added, removed = f.removed }
    end, s.files),
  }
end

function M.print_status()
  local st = M.status()
  local msg
  if not st.active then
    msg = 'prflow: inactive'
  elseif not st.ready then
    msg = ('prflow: loading %s...'):format(st.ref)
  else
    local against = st.mode == 'base' and st.ref or st.mode
    msg = ('prflow: %s vs %s (%s), %d files'):format(st.branch, against, st.base:sub(1, 7), #st.files)
  end
  vim.api.nvim_echo({ { msg } }, false, {})
end

-- Hunks of a changed file, computed on demand.
function M.hunks(path)
  local s = core().session
  local file = s and s.ready and s.by_path[path]
  return file and core().ensure_hunks(file) or nil
end

return M
