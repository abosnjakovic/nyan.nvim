local diagnostics = require("nyan.providers.diagnostics")

describe("providers.diagnostics", function()
  local buf

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local lines = {}
    for i = 1, 100 do
      lines[i] = "line " .. i
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end)

  after_each(function()
    vim.diagnostic.reset(nil, buf)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns empty list when no diagnostics", function()
    local result = diagnostics.get(buf)
    assert.same({}, result)
  end)

  it("returns diagnostics with line and severity", function()
    vim.diagnostic.set(vim.api.nvim_create_namespace("test"), buf, {
      { lnum = 9, col = 0, message = "error", severity = vim.diagnostic.severity.ERROR },
      { lnum = 49, col = 0, message = "warn", severity = vim.diagnostic.severity.WARN },
    })

    local result = diagnostics.get(buf)
    assert.equals(2, #result)
    assert.equals(10, result[1].line) -- 0-indexed lnum + 1 = 1-indexed line
    assert.equals(vim.diagnostic.severity.ERROR, result[1].severity)
    assert.equals(50, result[2].line)
    assert.equals(vim.diagnostic.severity.WARN, result[2].severity)
  end)

  it("returns empty list for invalid buffer", function()
    local result = diagnostics.get(99999)
    assert.same({}, result)
  end)
end)
