-- Review mode without commands: start in any git repo, follow HEAD and :cd.
local core = require('prflow.core')
local git = require('prflow.git')

local M = {}

local uv = vim.uv or vim.loop
local last_check = 0

local function start()
  require('prflow').start(nil, { quiet = true })
end

-- Reloads the session when HEAD or the branch changed outside Neovim.
function M.check()
  local s = core.session
  if not (s and s.ready) or uv.now() - last_check < 1000 then
    return
  end
  last_check = uv.now()
  git.run(s.root, { 'rev-parse', 'HEAD', '--abbrev-ref', 'HEAD' }, function(out)
    local head, branch = unpack(vim.split(vim.trim(out), '\n'))
    if core.session == s and (head ~= s.head or branch ~= s.branch) then
      require('prflow').start(s.ref_arg, { quiet = s.quiet })
    end
  end, function() end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('prflow_auto', { clear = true })
  if vim.v.vim_did_enter == 1 then
    start()
  else
    vim.api.nvim_create_autocmd('VimEnter', { group = group, once = true, callback = start })
  end
  vim.api.nvim_create_autocmd('DirChanged', { group = group, callback = start })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'FocusGained' }, { group = group, callback = M.check })
end

return M
