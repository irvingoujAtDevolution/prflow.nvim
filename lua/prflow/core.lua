-- Review session: the one piece of global state behind review mode.
local config = require('prflow.config')
local diff = require('prflow.diff')
local git = require('prflow.git')
local state = require('prflow.state')

local M = {}

M.session = nil

local uv = vim.uv or vim.loop
local is_win = vim.fn.has('win32') == 1

local function key(path)
  path = vim.fs.normalize(path)
  return is_win and path:lower() or path
end

local function current(s, gen)
  return M.session == s and s.gen == gen
end

local function strip_cr(lines)
  for i, l in ipairs(lines) do
    if l:sub(-1) == '\r' then
      lines[i] = l:sub(1, -2)
    end
  end
  return lines
end

function M.abs(path)
  return M.session.root .. '/' .. path
end

function M.file_for_buf(buf)
  local s = M.session
  if not s or not s.ready or not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  local path = vim.b[buf].prflow_path
  if path then
    return s.by_path[path]
  end
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= '' and s.by_key[key(name)] or nil
end

function M.bufs_for(file)
  local out = {}
  for buf, f in pairs(M.session.attached) do
    if f == file and vim.api.nvim_buf_is_loaded(buf) then
      out[#out + 1] = buf
    end
  end
  table.sort(out)
  return out
end

local function new_lines(file)
  if file.status == 'D' then
    return {}
  end
  local buf = M.bufs_for(file)[1]
  if buf then
    return strip_cr(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end
  return strip_cr(vim.fn.readfile(M.abs(file.path)))
end

function M.render(file)
  local render = require('prflow.render')
  for _, buf in ipairs(M.bufs_for(file)) do
    render.buf(buf, file)
  end
  require('prflow.tree').refresh()
end

function M.recompute(file)
  file.hunks = diff.hunks(file.path, file.base_lines, new_lines(file))
  M.render(file)
end

function M.with_base(file, cb)
  if file.base_lines then
    return cb()
  end
  if file.status == 'A' then
    file.base_lines = {}
    return cb()
  end
  if file.waiters then
    table.insert(file.waiters, cb)
    return
  end
  file.waiters = { cb }
  local s = M.session
  local gen = s.gen
  git.show(s.root, s.base, file.old_path, function(lines)
    if not current(s, gen) then
      return
    end
    file.base_lines = file.base_lines or lines
    local waiters = file.waiters
    file.waiters = nil
    for _, w in ipairs(waiters) do
      w()
    end
  end)
end

function M.ensure_hunks(file)
  if not file.hunks then
    if not file.base_lines then
      local s = M.session
      file.base_lines = file.status == 'A' and {} or git.show_sync(s.root, s.base, file.old_path)
    end
    M.recompute(file)
  end
  return file.hunks
end

function M.schedule(buf)
  local s = M.session
  local timer = s.timers[buf]
  if not timer then
    timer = assert(uv.new_timer())
    s.timers[buf] = timer
  end
  timer:stop()
  timer:start(config.get().debounce_ms, 0, vim.schedule_wrap(function()
    local file = M.session == s and s.attached[buf]
    if file and file.base_lines and vim.api.nvim_buf_is_loaded(buf) then
      M.recompute(file)
    end
  end))
end

function M.detach(buf)
  local s = M.session
  if not s then
    return
  end
  s.attached[buf] = nil
  local timer = s.timers[buf]
  if timer then
    timer:stop()
    timer:close()
    s.timers[buf] = nil
  end
end

function M.attach(buf)
  local s = M.session
  local file = M.file_for_buf(buf)
  if not file then
    return
  end
  if not s.attached[buf] then
    s.attached[buf] = file
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      group = s.group,
      buffer = buf,
      callback = function()
        M.schedule(buf)
      end,
    })
    vim.api.nvim_create_autocmd('BufWipeout', {
      group = s.group,
      buffer = buf,
      callback = function()
        M.detach(buf)
      end,
    })
  end
  M.with_base(file, function()
    if s.attached[buf] == file and vim.api.nvim_buf_is_loaded(buf) then
      M.recompute(file)
    end
  end)
end

local function reset(s)
  require('prflow.render').clear_all()
  for _, buf in pairs(s.scratch) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  for buf in pairs(s.attached) do
    M.detach(buf)
  end
  s.attached, s.scratch, s.files, s.by_path, s.by_key = {}, {}, {}, {}, {}
  s.ready = false
  require('prflow.tree').refresh()
end

local function set_files(s, out)
  local files = git.parse_name_status(out.status)
  local counts = git.parse_numstat(out.numstat)
  for _, f in ipairs(files) do
    local c = counts[f.path]
    if c then
      f.added, f.removed = c.added, c.removed
    end
  end
  for _, path in ipairs(git.split0(out.untracked)) do
    files[#files + 1] = { path = path, old_path = path, status = 'A', untracked = true }
  end
  s.files = require('prflow.stream').order(files)
  for i, f in ipairs(s.files) do
    f.index = i
    s.by_path[f.path] = f
    if f.status ~= 'D' then
      s.by_key[key(M.abs(f.path))] = f
    end
  end
end

-- Quiet (auto-started) sessions end silently on failure; manual ones raise.
local function fail(s, msg)
  if not s.quiet then
    error(msg, 0)
  end
  if M.session == s then
    s.on_fail()
  end
end

local function on_err(s)
  return s.quiet and function()
    fail(s)
  end or nil
end

local function resolve(s, range, cb)
  local function trimmed(out)
    cb(vim.trim(out))
  end
  if range.mode == 'base' then
    if s.ref then
      return git.run(s.root, { 'merge-base', s.ref, 'HEAD' }, trimmed, on_err(s))
    end
    git.default_base(s.root, function(ref)
      if not ref then
        return fail(s, 'prflow: no origin/HEAD, origin/main or origin/master; pass a ref to :PrflowStart or set vim.g.prflow.base')
      end
      s.ref = ref
      git.run(s.root, { 'merge-base', ref, 'HEAD' }, trimmed, on_err(s))
    end)
  elseif range.mode == 'commit' then
    git.run(s.root, { 'rev-parse', '--verify', range.rev .. '^{commit}' }, trimmed, on_err(s))
  elseif range.mode == 'since-review' then
    cb(M.branch_state().reviewed_head)
  else
    error(('prflow: unknown range mode %q'):format(range.mode))
  end
end

function M.branch_state()
  local s = M.session
  return state.branch(s.state, s.branch)
end

function M.is_viewed(h)
  return M.branch_state().viewed[h.hash] == true
end

function M.save_state()
  state.save(M.session.gitdir, M.session.state)
end

function M.load(range)
  local s = M.session
  s.gen = s.gen + 1
  local gen = s.gen
  reset(s)
  s.range = range
  resolve(s, range, function(base)
    if not current(s, gen) then
      return
    end
    s.base = base
    local out, pending = {}, 3
    local function done(field)
      return function(stdout)
        out[field] = stdout
        pending = pending - 1
        if pending > 0 or not current(s, gen) then
          return
        end
        set_files(s, out)
        s.ready = true
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buf) then
            M.attach(buf)
          end
        end
        require('prflow.tree').refresh()
      end
    end
    git.run(s.root, { 'diff', '--name-status', '-M', '-z', base }, done('status'), on_err(s))
    git.run(s.root, { 'diff', '--numstat', '-M', '-z', base }, done('numstat'), on_err(s))
    git.run(s.root, { 'ls-files', '--others', '--exclude-standard', '-z' }, done('untracked'), on_err(s))
  end)
end

-- opts.quiet: return false instead of raising when cwd is not a usable repo,
-- and call opts.on_fail() if a later async step fails.
function M.start(ref, opts)
  opts = opts or {}
  M.stop()
  local ok, repo = pcall(git.repo, vim.fn.getcwd())
  if not ok then
    if opts.quiet then
      return false
    end
    error(repo, 0)
  end
  local s = {
    root = repo.root,
    gitdir = repo.gitdir,
    branch = repo.branch,
    head = repo.head,
    ref_arg = ref,
    quiet = opts.quiet,
    on_fail = opts.on_fail,
    ref = ref or config.get().base,
    gen = 0,
    group = vim.api.nvim_create_augroup('prflow', { clear = true }),
    attached = {},
    scratch = {},
    timers = {},
    files = {},
    by_path = {},
    by_key = {},
    ready = false,
    state = state.load(repo.gitdir),
  }
  M.session = s
  vim.api.nvim_create_autocmd('BufReadPost', {
    group = s.group,
    callback = function(ev)
      M.attach(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = s.group,
    callback = function()
      require('prflow.tree').track(vim.api.nvim_get_current_win())
    end,
  })
  vim.api.nvim_create_autocmd('BufEnter', {
    group = s.group,
    callback = function()
      require('prflow.tree').refresh()
    end,
  })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = s.group,
    callback = function()
      require('prflow.render').define_highlights()
    end,
  })
  M.load({ mode = 'base' })
  return true
end

function M.stop()
  local s = M.session
  if not s then
    return
  end
  reset(s)
  vim.api.nvim_del_augroup_by_id(s.group)
  M.session = nil
end

return M
