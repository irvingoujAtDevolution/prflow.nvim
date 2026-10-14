local fixture = require('tests.helpers.fixture')
local H = require('tests.helpers.child')
local eq = MiniTest.expect.equality

local child = H.new()
local fx

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      fx = fixture.standard()
      H.boot(child, fx.root)
      H.start(child)
    end,
    post_case = function()
      child.stop()
      fixture.cleanup(fx)
    end,
  },
})

local function wait_rendered()
  H.wait(child, "#vim.api.nvim_buf_get_extmarks(0, require('prflow.render').ns, 0, -1, {}) > 0")
end

-- { line_hl = { rows }, virt = { [row] = { above, texts } } } for the current buffer.
local function summary()
  return child.lua_get([[(function()
    local out = { line_hl = {}, virt = {} }
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, require('prflow.render').ns, 0, -1, { details = true })) do
      local row, d = m[2], m[4]
      if d.hl_group == 'PrflowAdd' and d.hl_eol then table.insert(out.line_hl, row) end
      if d.virt_lines then
        local texts = {}
        for _, vl in ipairs(d.virt_lines) do
          local t = ''
          for _, chunk in ipairs(vl) do t = t .. chunk[1] end
          table.insert(texts, vim.trim(t))
        end
        out.virt[tostring(row)] = { d.virt_lines_above or false, texts }
      end
    end
    table.sort(out.line_hl)
    return out
  end)()]])
end

T['renders A with line highlights and inline deleted lines'] = function()
  child.cmd('edit A')
  wait_rendered()
  local s = summary()
  eq(s.line_hl, { 2, 18, 19, 27 })
  eq(s.virt, {
    ['2'] = { true, { 'line 3' } },
    ['9'] = { true, { 'line 10', 'line 11' } },
    ['27'] = { true, { 'line 28' } },
  })
  local signs = child.lua_get([[vim.tbl_map(function(m) return m[4].sign_text end,
    vim.api.nvim_buf_get_extmarks(0, require('prflow.render').ns, 0, -1, { details = true, type = 'sign' }))]])
  MiniTest.expect.no_equality(#signs, 0)
end

T['renders buffers opened after start'] = function()
  child.cmd('edit F')
  wait_rendered()
  eq(summary().line_hl, { 0, 1, 2 })
end

T['stop clears every extmark in every buffer'] = function()
  child.cmd('edit A')
  wait_rendered()
  child.cmd('edit F')
  wait_rendered()
  child.cmd('PrflowStop')
  local total = child.lua_get([[(function()
    local n = 0
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      n = n + #vim.api.nvim_buf_get_extmarks(b, require('prflow.render').ns, 0, -1, {})
    end
    return n
  end)()]])
  eq(total, 0)
end

T['screenshot shows deleted lines inline'] = function()
  child.cmd('edit A')
  wait_rendered()
  child.cmd('normal! 5Gzt')
  local shot = child.get_screenshot()
  local rows = {}
  for i, line in ipairs(shot.text) do
    rows[i] = (table.concat(line):gsub('%s+$', ''))
  end
  local function find(suffix)
    for i, r in ipairs(rows) do
      if r:sub(-#suffix) == suffix then
        return i
      end
    end
  end
  local at = find('line 9')
  MiniTest.expect.no_equality(at, nil)
  eq(rows[at + 1]:match('line 10$') ~= nil, true)
  eq(rows[at + 2]:match('line 11$') ~= nil, true)
  eq(rows[at + 3]:match('line 12$') ~= nil, true)
end

return T
