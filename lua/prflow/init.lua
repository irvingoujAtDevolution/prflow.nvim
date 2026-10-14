local M = {}

local function core()
  return require('prflow.core')
end

function M.setup(opts)
  vim.g.prflow = vim.tbl_deep_extend('force', vim.g.prflow or {}, opts or {})
end

-- Mappings that review mode replaced, restored on stop.
local saved = {}

local function unmap()
  for lhs, prev in pairs(saved) do
    pcall(vim.keymap.del, 'n', lhs)
    if prev ~= false then
      vim.fn.mapset('n', false, prev)
    end
  end
  saved = {}
end

local function map()
  local keys = require('prflow.config').get().keys
  local actions = {
    { keys.next, function() require('prflow.stream').step(1) end, 'prflow: next hunk' },
    { keys.prev, function() require('prflow.stream').step(-1) end, 'prflow: previous hunk' },
    { keys.hunk, function() M.hunk() end, 'prflow: hunk side by side' },
    { keys.viewed, function() M.toggle_viewed() end, 'prflow: toggle hunk viewed' },
  }
  for _, a in ipairs(actions) do
    local lhs = a[1]
    if lhs and lhs ~= '' then
      local prev = vim.fn.maparg(lhs, 'n', false, true)
      saved[lhs] = (prev.buffer == 0 and prev.lhs) and prev or false
      vim.keymap.set('n', lhs, a[2], { desc = a[3] })
    end
  end
end

function M.start(ref)
  unmap()
  core().start(ref)
  map()
end

function M.stop()
  unmap()
  require('prflow.float').close()
  core().stop()
end

function M.hunk()
  require('prflow.float').open()
end

local function active()
  local s = core().session
  if s and s.ready then
    return s
  end
  vim.notify('prflow: not in review mode', vim.log.levels.WARN)
end

function M.toggle_viewed()
  if not active() then
    return
  end
  local file, h = require('prflow.stream').hunk_at_cursor()
  if not h then
    return vim.notify('prflow: no hunk under cursor', vim.log.levels.WARN)
  end
  local viewed = core().branch_state().viewed
  viewed[h.hash] = (not viewed[h.hash]) or nil
  core().save_state()
  core().render(file)
end

function M.mark_reviewed()
  local s = active()
  if not s then
    return
  end
  local head = vim.trim(require('prflow.git').run_sync(s.root, { 'rev-parse', 'HEAD' }))
  core().branch_state().reviewed_head = head
  core().save_state()
  vim.notify(('prflow: marked %s as reviewed'):format(head:sub(1, 7)))
end

-- `base`, `commit <sha>` or `since-review`.
function M.range(mode, rev)
  if not active() then
    return
  end
  if mode == 'commit' and not rev then
    return vim.notify('prflow: usage :PrflowRange commit <sha>', vim.log.levels.ERROR)
  end
  if mode == 'since-review' and not core().branch_state().reviewed_head then
    return vim.notify('prflow: no review recorded, run :PrflowMarkReviewed first', vim.log.levels.ERROR)
  end
  if mode ~= 'base' and mode ~= 'commit' and mode ~= 'since-review' then
    return vim.notify(('prflow: unknown range %q'):format(tostring(mode)), vim.log.levels.ERROR)
  end
  core().load({ mode = mode, rev = rev })
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

function M.files()
  require('prflow.picker').pick()
end

-- Hunks of a changed file, computed on demand.
function M.hunks(path)
  local s = core().session
  local file = s and s.ready and s.by_path[path]
  return file and core().ensure_hunks(file) or nil
end

return M
