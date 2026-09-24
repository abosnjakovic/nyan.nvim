if os.getenv("NYAN_COVERAGE") then
  local home = os.getenv("HOME") or ""
  local lr_share = home .. "/.luarocks/share/lua/5.1"
  local lr_lib = home .. "/.luarocks/lib/lua/5.1"
  package.path = lr_share .. "/?.lua;" .. lr_share .. "/?/init.lua;" .. package.path
  package.cpath = lr_lib .. "/?.so;" .. package.cpath
  local ok, runner = pcall(require, "luacov.runner")
  if not ok then
    io.stderr:write("luacov.runner load failed: " .. tostring(runner) .. "\n")
  else
    local pid = tostring((vim.uv and vim.uv.getpid and vim.uv.getpid()) or vim.loop.getpid())
    runner.init({ statsfile = ".luacov.stats." .. pid .. ".out" })
    vim.api.nvim_create_autocmd("VimLeavePre", {
      callback = function()
        if runner.save_stats then
          runner.save_stats()
        end
      end,
    })
  end
end

local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
local is_not_a_directory = vim.fn.isdirectory(plenary_dir) == 0
if is_not_a_directory then
  vim.fn.system({"git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir})
end

-- macOS's /tmp cleanup deletes old files but keeps directories, leaving a
-- hollow clone that the check above accepts. plenary would then fail to load
-- and headless nvim would sit waiting forever, so exit with the fix instead.
if vim.fn.filereadable(plenary_dir .. "/lua/plenary/busted.lua") == 0 then
  io.stderr:write("plenary.nvim at " .. plenary_dir .. " is incomplete: delete it, or set PLENARY_DIR\n")
  vim.cmd("cquit 1")
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
