--- Headless e2e entrypoint. Run with:
---   TERM_PROGRAM=ghostty nvim --clean --headless -l tests/e2e/emit_setup.lua
---
--- Runs a full, unmodified `nyan.setup()` in a real nvim process so the actual
--- Kitty graphics byte stream lands on fd 1 (stdout). An external harness
--- captures that stream and asserts the on-the-wire protocol -- the integration
--- that the in-process io.write mock in kitty_spec cannot see.
---
--- Graphics are emitted synchronously during setup() (load_sprites ->
--- transmit_image/create_virtual_placement), so no animation timer runs and the
--- stream is deterministic. Animation is disabled to keep it that way. The
--- images are deleted again by the VimLeavePre autocmd when this script exits.

vim.opt.rtp:append(".")

local ok, err = pcall(function()
  require("nyan").setup({
    renderer = "nyan",
    animation = { enabled = false },
  })
end)

io.flush()

if not ok then
  io.stderr:write("emit_setup failed: " .. tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
