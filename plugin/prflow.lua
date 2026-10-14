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

command('PrflowHunk', function()
  require('prflow').hunk()
end)
