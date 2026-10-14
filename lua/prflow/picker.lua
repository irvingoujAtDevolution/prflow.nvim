local core = require('prflow.core')
local stream = require('prflow.stream')

local M = {}

-- Live counts once a file's hunks exist, git's numstat before that.
function M.counts(file)
  if file.hunks then
    local added, removed = 0, 0
    for _, h in ipairs(file.hunks) do
      added, removed = added + h.new_count, removed + h.old_count
    end
    return added, removed
  end
  if file.untracked then
    return #vim.fn.readfile(core.abs(file.path)), 0
  end
  return file.added or 0, file.removed or 0
end

function M.items()
  return vim.tbl_map(function(f)
    local added, removed = M.counts(f)
    return { file = f, text = ('%s %s +%d -%d'):format(f.status, f.path, added, removed) }
  end, core.session.files)
end

function M.open(item)
  local hunk = core.ensure_hunks(item.file)[1]
  if hunk then
    stream.jump(item.file, hunk)
  else
    stream.open(item.file)
  end
end

function M.pick()
  local s = core.session
  if not (s and s.ready) then
    return vim.notify('prflow: not in review mode', vim.log.levels.WARN)
  end
  local items = M.items()
  local ok, snacks = pcall(require, 'snacks')
  if ok and snacks.picker then
    snacks.picker.pick({
      source = 'prflow_files',
      title = 'prflow: changed files',
      format = 'text',
      items = vim.tbl_map(function(it)
        return { text = it.text, file = it.file.status ~= 'D' and core.abs(it.file.path) or nil, prflow = it }
      end, items),
      confirm = function(picker, item)
        picker:close()
        if item then
          M.open(item.prflow)
        end
      end,
    })
    return
  end
  vim.ui.select(items, {
    prompt = 'prflow: changed files',
    format_item = function(it)
      return it.text
    end,
  }, function(it)
    if it then
      M.open(it)
    end
  end)
end

return M
