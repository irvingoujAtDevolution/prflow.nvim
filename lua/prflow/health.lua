local M = {}

local function git(args, cwd)
  return vim.system(vim.list_extend({ 'git' }, args), { cwd = cwd, text = true }):wait()
end

function M.check()
  local health = vim.health
  health.start('prflow')
  if vim.fn.has('nvim-0.10') == 1 then
    health.ok('Neovim ' .. tostring(vim.version()))
  else
    health.error('Neovim >= 0.10 is required')
  end
  if vim.fn.executable('git') == 0 then
    return health.error('git is not on PATH')
  end
  health.ok(vim.trim(git({ '--version' }).stdout))
  local s = require('prflow.core').session
  local cwd = s and s.root or vim.fn.getcwd()
  if git({ 'rev-parse', '--show-toplevel' }, cwd).code ~= 0 then
    return health.warn('Not inside a git repository: ' .. cwd)
  end
  local ref = s and s.ref or require('prflow.config').get().base or require('prflow.git').default_base_sync(cwd)
  if not ref then
    return health.error('No base ref: origin/HEAD, origin/main and origin/master are all missing', {
      'Run `git fetch`, or set `vim.g.prflow.base`',
    })
  end
  if git({ 'rev-parse', '--verify', '--quiet', ref .. '^{commit}' }, cwd).code == 0 then
    health.ok(('Base ref %s exists'):format(ref))
  else
    health.error(('Base ref %s does not exist'):format(ref), { 'Run `git fetch`, or set `vim.g.prflow.base`' })
  end
end

return M
