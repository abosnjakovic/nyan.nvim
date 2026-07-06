--- End-to-end: assert the real Kitty graphics wire protocol.
---
--- Spawns a real, unmodified nvim (tests/e2e/emit_setup.lua), captures its
--- stdout, and checks the actual bytes nyan puts on the wire during a full
--- setup + exit. Unlike kitty_spec (which mocks io.write in-process), this
--- exercises the init.lua load_sprites wiring, real PNG assets, and the
--- VimLeavePre cleanup, all in a separate process.
---
--- POSIX only: uses a shell redirect and inherits env. Skipped on Windows,
--- where a terminal-graphics e2e is not a target anyway.

local kitty = require("nyan.kitty")

-- Count non-overlapping literal occurrences of `needle` in `s`.
local function count(s, needle)
  local n, from = 0, 1
  while true do
    local i = s:find(needle, from, true)
    if not i then
      return n
    end
    n = n + 1
    from = i + #needle
  end
end

describe("e2e: kitty graphics wire protocol", function()
  -- Capture once: spawn a real nvim and read the graphics bytes it writes to fd 1.
  local stream = ""
  if vim.fn.has("win32") == 0 then
    local script = vim.fn.fnamemodify("tests/e2e/emit_setup.lua", ":p")
    local out = vim.fn.tempname()
    -- TERM_PROGRAM=ghostty so kitty.is_supported() is true and sprites transmit.
    -- env -u TMUX so the stream is not tmux-passthrough-wrapped (deterministic).
    vim.fn.system(
      string.format(
        "env -u TMUX TERM_PROGRAM=ghostty nvim --clean --headless -l %s > %s 2>/dev/null",
        vim.fn.shellescape(script),
        vim.fn.shellescape(out)
      )
    )
    stream = kitty.read_file(out) or ""
    os.remove(out)
  end

  it("emits Kitty graphics to a real fd (not just the mock)", function()
    if vim.fn.has("win32") == 1 then
      pending("POSIX-only e2e harness")
      return
    end
    assert.is_true(#stream > 0, "captured stdout was empty -- setup() emitted nothing")
    assert.is_true(stream:find("\027_G", 1, true) ~= nil, "no APC graphics opener on the wire")
  end)

  it("transmits every sprite and gives each a virtual placement", function()
    if vim.fn.has("win32") == 1 then
      pending("POSIX-only e2e harness")
      return
    end
    local transmits = count(stream, "a=t,f=100,i=")
    local placements = count(stream, "a=p,U=1,i=")
    -- 6 cat frames are the core; rainbow makes 7. Assert the wiring invariant:
    -- load_sprites pairs one placement with every transmit.
    assert.is_true(transmits >= 6, "expected >=6 sprite transmits, got " .. transmits)
    assert.equals(transmits, placements)
  end)

  it("cleans up every transmitted image on exit (no leak)", function()
    if vim.fn.has("win32") == 1 then
      pending("POSIX-only e2e harness")
      return
    end
    -- VimLeavePre -> delete_all_images emits one a=d,d=I per transmitted id.
    local transmits = count(stream, "a=t,f=100,i=")
    local deletes = count(stream, "a=d,d=I,i=")
    assert.equals(transmits, deletes)
  end)

  it("every APC command is terminated by ST (well-formed)", function()
    if vim.fn.has("win32") == 1 then
      pending("POSIX-only e2e harness")
      return
    end
    -- All real assets are single-chunk, so openers and ST terminators pair 1:1.
    assert.equals(count(stream, "\027_G"), count(stream, "\027\\"))
  end)

  it("carries a real PNG that base64-decodes intact over the wire", function()
    if vim.fn.has("win32") == 1 then
      pending("POSIX-only e2e harness")
      return
    end
    -- Grab the payload of the first single-chunk transmit and decode it.
    local b64 = stream:match("a=t,f=100,i=%d+,q=2;([A-Za-z0-9+/=]+)\027\\")
    assert.is_truthy(b64, "could not extract a base64 transmit payload")
    local png = vim.base64.decode(b64)
    -- PNG magic: 0x89 'P' 'N' 'G'
    assert.equals("\137PNG", png:sub(1, 4))
  end)
end)
