local function command(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

command('PrflowStart', function(o)
  require('prflow').start(o.args ~= '' and o.args or nil)
end, { nargs = '?' })

command('PrflowStop', function()
  require('prflow').stop()
end)

command('PrflowStatus', function()
  require('prflow').print_status()
end)

command('PrflowFiles', function()
  require('prflow').files()
end)

command('PrflowTree', function()
  require('prflow').tree()
end)

command('PrflowHunk', function()
  require('prflow').hunk()
end)

command('PrflowRange', function(o)
  require('prflow').range(o.fargs[1], o.fargs[2])
end, {
  nargs = '+',
  complete = function(_, line)
    return vim.fn.len(vim.split(line, '%s+')) <= 2 and { 'base', 'commit', 'since-review' } or {}
  end,
})

command('PrflowMarkReviewed', function()
  require('prflow').mark_reviewed()
end)

command('PrflowHelp', function()
  require('prflow').help()
end)

-- Deferred a tick: lazy.nvim applies `opts` right after sourcing this file.
vim.schedule(function()
  if require('prflow.config').get().auto then
    require('prflow.auto').setup()
  end
end)
