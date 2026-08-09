# Search-Hit Markers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Draw lines matching the current search pattern as `◆` markers on the space renderer's minimap, updating live as the user types in the `/` command line.

**Architecture:** A new provider module, `nyan.providers.search`, follows the existing `providers/git.lua` shape — `get(bufnr)` returns `{ line = N }[]`, backed by a per-buffer cache with explicit invalidation. The space renderer consumes it as a third marker source at top collision priority. `init.lua` pushes the in-progress command-line pattern into the provider from `CmdlineChanged`, because `vim.fn.getcmdline()` is only meaningful while the command line is genuinely active.

**Tech Stack:** Lua 5.1 / LuaJIT, Neovim 0.10+ API, plenary.nvim (busted-style tests), stylua, luacheck.

**Spec:** `docs/superpowers/specs/2026-08-09-search-markers-design.md`

## Global Constraints

- Neovim 0.10 is the floor. Do not use an API newer than 0.10 without an existence guard.
- No new runtime dependencies. gitsigns stays optional; nothing else gets added.
- Lua 5.1 / LuaJIT syntax only — no integer division `//`, no goto-as-identifier, no `<close>`.
- Every module returns a local table named `M`. Public functions are `M.name = function(...)`, matching every existing module.
- Public functions carry LuaCATS annotations (`---@param`, `---@return`) like the rest of `lua/nyan/`.
- Formatting is enforced by stylua (`.stylua.toml`: 2-space indent, 120 column width). Run `make lint` before every commit.
- Static analysis is enforced by luacheck (`.luacheckrc`). Run `make lint-luacheck` before every commit.
- This repository uses **GitButler**. Use `but commit`, never `git commit`. All work goes on the existing branch `feat/search-markers`.
- `doc/nyan.txt` is generated from `README.md` by panvimdoc during release (`.github/workflows/release.yml:36`). Edit `README.md` only; never hand-edit `doc/nyan.txt`.

## Reference: How to run tests

Full suite:

```bash
make test
```

Single file (much faster while iterating):

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/nyan/providers/search_spec.lua"
```

Plenary prints `Success: N` / `Failed : N` / `Errors : N` at the end. A file that fails to load reports `Errors`, not `Failed`.

## Reference: Verified API behaviour

These were confirmed by probe against the local Neovim before this plan was written. Do not re-derive them:

| Call | Behaviour |
|---|---|
| `vim.v.hlsearch = 1` | Writable, provided `vim.o.hlsearch` is `true` first |
| `vim.fn.setreg("/", "foo")` | Sets the last-search register; does **not** change `v:hlsearch` |
| `vim.fn.match("hello", "foo\\(")` | **Throws** `Vim:E54: Unmatched \(` |
| `vim.fn.match("foo", "Foo")` with `ignorecase` on | `0` (matches) |
| `vim.fn.match("foo", "\\CFoo")` with `ignorecase` on | `-1` (forced case-sensitive) |
| `("\\Vfoo"):gsub("\\.", ""):find("%u")` | `nil` — escapes stripped, no uppercase |
| `("Foo"):gsub("\\.", ""):find("%u")` | `1` — real uppercase detected |
| `vim.fn.getcmdtype = function() ... end` | Assignment works; `vim.fn` entries are stubbable in tests |
| `vim.api.nvim_exec_autocmds("CmdlineChanged", { group = g })` | Fires the callback; no `pattern` needed |
| `vim.api.nvim__redraw({ statusline = true })` | Present and callable on 0.10+ |

## File Structure

| File | Responsibility |
|---|---|
| `lua/nyan/providers/search.lua` (create) | Resolve the active search pattern, scan the buffer, cache the result |
| `tests/nyan/providers/search_spec.lua` (create) | Provider unit tests |
| `lua/nyan/config.lua` (modify) | One new `search` boolean field |
| `lua/nyan/renderers/space.lua` (modify) | Consume the provider; `◆` at top collision priority |
| `tests/nyan/renderers/space_spec.lua` (modify) | Renderer integration tests |
| `lua/nyan/init.lua` (modify) | Command-line autocommands that push the live pattern |
| `tests/nyan/nyan_spec.lua` (modify) | Autocommand wiring tests |
| `tests/nyan/config_spec.lua` (modify) | Close the `config.lua` coverage gap |
| `README.md` (modify) | User-facing documentation |

---

### Task 1: Search provider

**Files:**
- Create: `lua/nyan/providers/search.lua`
- Test: `tests/nyan/providers/search_spec.lua`

**Interfaces:**
- Consumes: nothing — this task has no dependencies on other tasks.
- Produces:
  - `M.set_live(pattern: string): nil`
  - `M.clear_live(): nil`
  - `M.get(bufnr: number): { line: number }[]` — `line` is 1-indexed
  - `M.invalidate(bufnr: number): nil`
  - `M.invalidate_all(): nil`
  - `M._scan_count: number` — test-only counter, starts at `0`

- [ ] **Step 1: Write the failing test**

Create `tests/nyan/providers/search_spec.lua` with this exact content:

```lua
local search = require("nyan.providers.search")

describe("providers.search", function()
  local buf

  before_each(function()
    search.clear_live()
    search.invalidate_all()
    search._scan_count = 0

    -- Start from a known option state; individual tests override as needed.
    vim.o.hlsearch = true
    vim.o.ignorecase = false
    vim.o.smartcase = false
    vim.v.hlsearch = 0
    vim.fn.setreg("/", "")

    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    -- Lines 1..100. "target" appears on lines 3 and 7 only.
    local lines = {}
    for i = 1, 100 do
      lines[i] = "line " .. i
    end
    lines[3] = "target here"
    lines[7] = "another target"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end)

  after_each(function()
    search.clear_live()
    search.invalidate_all()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  describe("pattern resolution", function()
    it("returns empty list when no pattern is set", function()
      assert.same({}, search.get(buf))
    end)

    it("returns empty list when hlsearch is off, even with a register pattern", function()
      vim.fn.setreg("/", "target")
      vim.v.hlsearch = 0
      assert.same({}, search.get(buf))
    end)

    it("returns 1-indexed matching lines from the register when hlsearch is on", function()
      vim.fn.setreg("/", "target")
      vim.v.hlsearch = 1

      local result = search.get(buf)
      assert.equals(2, #result)
      assert.equals(3, result[1].line)
      assert.equals(7, result[2].line)
    end)

    it("set_live overrides the register pattern", function()
      vim.fn.setreg("/", "target")
      vim.v.hlsearch = 1
      search.set_live("line 42")

      local result = search.get(buf)
      assert.equals(1, #result)
      assert.equals(42, result[1].line)
    end)

    it("clear_live restores register behaviour", function()
      vim.fn.setreg("/", "target")
      vim.v.hlsearch = 1
      search.set_live("line 42")
      search.get(buf)

      search.clear_live()
      local result = search.get(buf)
      assert.equals(2, #result)
      assert.equals(3, result[1].line)
    end)

    it("an empty live pattern marks nothing and does not fall back to the register", function()
      vim.fn.setreg("/", "target")
      vim.v.hlsearch = 1
      search.set_live("")

      assert.same({}, search.get(buf))
    end)
  end)

  describe("invalid patterns", function()
    it("returns empty list instead of throwing on a half-typed regex", function()
      search.set_live("target\\(")

      local result
      assert.has_no.errors(function()
        result = search.get(buf)
      end)
      assert.same({}, result)
    end)
  end)

  describe("case sensitivity", function()
    before_each(function()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "lower target", "UPPER TARGET" })
    end)

    it("is case-sensitive when ignorecase is off", function()
      vim.o.ignorecase = false
      search.set_live("TARGET")

      local result = search.get(buf)
      assert.equals(1, #result)
      assert.equals(2, result[1].line)
    end)

    it("is case-insensitive when ignorecase is on and smartcase is off", function()
      vim.o.ignorecase = true
      vim.o.smartcase = false
      search.set_live("TARGET")

      assert.equals(2, #search.get(buf))
    end)

    it("stays case-insensitive with smartcase on and an all-lowercase pattern", function()
      vim.o.ignorecase = true
      vim.o.smartcase = true
      search.set_live("target")

      assert.equals(2, #search.get(buf))
    end)

    it("becomes case-sensitive with smartcase on and an uppercase pattern", function()
      vim.o.ignorecase = true
      vim.o.smartcase = true
      search.set_live("TARGET")

      local result = search.get(buf)
      assert.equals(1, #result)
      assert.equals(2, result[1].line)
    end)

    it("does not treat a backslash-escaped uppercase as a smartcase trigger", function()
      vim.o.ignorecase = true
      vim.o.smartcase = true
      -- \V is very-nomagic, not an uppercase letter in the user's pattern.
      search.set_live("\\Vtarget")

      assert.equals(2, #search.get(buf))
    end)
  end)

  describe("caching", function()
    it("scans once for repeated calls on an unchanged buffer", function()
      search.set_live("target")

      search.get(buf)
      search.get(buf)
      search.get(buf)

      assert.equals(1, search._scan_count)
    end)

    it("rescans after the buffer changes", function()
      search.set_live("target")
      search.get(buf)

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "target", "target", "target" })
      local result = search.get(buf)

      assert.equals(2, search._scan_count)
      assert.equals(3, #result)
    end)

    it("rescans after invalidate", function()
      search.set_live("target")
      search.get(buf)

      search.invalidate(buf)
      search.get(buf)

      assert.equals(2, search._scan_count)
    end)

    it("rescans after invalidate_all", function()
      search.set_live("target")
      search.get(buf)

      search.invalidate_all()
      search.get(buf)

      assert.equals(2, search._scan_count)
    end)

    it("rescans when the pattern changes", function()
      search.set_live("target")
      search.get(buf)

      search.set_live("line 42")
      search.get(buf)

      assert.equals(2, search._scan_count)
    end)
  end)

  describe("limits", function()
    it("returns empty list for a buffer over the scan cap", function()
      local big = vim.api.nvim_create_buf(false, true)
      local lines = {}
      for i = 1, 20001 do
        lines[i] = "target"
      end
      vim.api.nvim_buf_set_lines(big, 0, -1, false, lines)
      search.set_live("target")

      assert.same({}, search.get(big))

      vim.api.nvim_buf_delete(big, { force = true })
    end)

    it("returns empty list for an invalid buffer", function()
      search.set_live("target")
      assert.same({}, search.get(99999))
    end)
  end)
end)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/nyan/providers/search_spec.lua"
```

Expected: `Errors : 1` — the file fails to load with `module 'nyan.providers.search' not found`.

- [ ] **Step 3: Write the implementation**

Create `lua/nyan/providers/search.lua` with this exact content:

```lua
local M = {}

-- ponytail: whole-buffer scan, capped at 20k lines. Make the cap configurable
-- or scan incrementally only if someone actually hits it on a real file.
local MAX_LINES = 20000

-- bufnr -> { key = string, result = table }
local cache = {}

-- Pattern currently being typed in the search command line, or nil when the
-- command line is closed. An empty string is meaningful: it means the user has
-- opened `/` but typed nothing, which should mark nothing.
local live_pattern = nil

-- Number of real buffer scans performed. Exposed for tests to assert the cache
-- works; nothing outside tests reads it.
M._scan_count = 0

--- Record the pattern being typed in the search command line
---@param pattern string
M.set_live = function(pattern)
  live_pattern = pattern
end

--- Forget the live pattern (search command line closed)
M.clear_live = function()
  live_pattern = nil
end

--- Decide which pattern to mark: the one being typed, else the last search
--- while 'hlsearch' is active.
---@return string? pattern nil when nothing should be marked
local function resolve_pattern()
  local pattern = live_pattern
  if pattern == nil then
    if vim.v.hlsearch == 0 then
      return nil
    end
    pattern = vim.fn.getreg("/")
  end
  if pattern == "" then
    return nil
  end
  return pattern
end

--- Apply the 'smartcase' semantics that vim.fn.match() does not implement.
--- match() honours 'ignorecase' but never 'smartcase', so the two disagree in
--- exactly one case: both options on and the pattern contains an uppercase
--- character. A real search is case-sensitive there, so force it with \C.
---@param pattern string
---@return string pattern Possibly \C-prefixed
local function apply_case(pattern)
  if vim.o.ignorecase and vim.o.smartcase then
    -- Strip backslash escapes first, so \V and friends do not read as
    -- uppercase. This is the same rule Vim itself applies.
    if pattern:gsub("\\.", ""):find("%u") then
      return "\\C" .. pattern
    end
  end
  return pattern
end

--- Scan every line of a buffer for a Vim regex
---@param bufnr number Buffer number
---@param pattern string Vim regex
---@return { line: number }[]
local function scan(bufnr, pattern)
  local read_ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not read_ok or #lines > MAX_LINES then
    return {}
  end

  M._scan_count = M._scan_count + 1

  local effective = apply_case(pattern)
  local result = {}
  -- A half-typed pattern such as "foo\(" makes match() throw E54. Every
  -- keystroke passes through states like that, so this is the common path,
  -- not a defensive edge case.
  local match_ok = pcall(function()
    for i, text in ipairs(lines) do
      if vim.fn.match(text, effective) >= 0 then
        table.insert(result, { line = i })
      end
    end
  end)
  if not match_ok then
    return {}
  end
  return result
end

--- Get search-hit markers for a buffer
---@param bufnr number Buffer number
---@return { line: number }[] Matching lines, 1-indexed
M.get = function(bufnr)
  local pattern = resolve_pattern()
  if not pattern then
    return {}
  end

  local tick_ok, changedtick = pcall(vim.api.nvim_buf_get_changedtick, bufnr)
  if not tick_ok then
    return {}
  end

  local key = pattern .. "\0" .. changedtick
  local entry = cache[bufnr]
  if entry and entry.key == key then
    return entry.result
  end

  local result = scan(bufnr, pattern)
  cache[bufnr] = { key = key, result = result }
  return result
end

--- Invalidate cache for a buffer
---@param bufnr number Buffer number
M.invalidate = function(bufnr)
  cache[bufnr] = nil
end

--- Invalidate all cached data
M.invalidate_all = function()
  cache = {}
end

return M
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/nyan/providers/search_spec.lua"
```

Expected: `Success: 19`, `Failed : 0`, `Errors : 0`.

- [ ] **Step 5: Run lint and the full suite**

```bash
make lint && make lint-luacheck && make test
```

Expected: stylua reports no diff, luacheck reports `0 warnings / 0 errors`, and the full suite passes with no new failures.

- [ ] **Step 6: Commit**

```bash
but diff
but commit -b feat/search-markers -m "feat(search): add search-hit provider for the space minimap" <file-ids>
```

Replace `<file-ids>` with the IDs `but diff` prints for `lua/nyan/providers/search.lua` and `tests/nyan/providers/search_spec.lua`. Do not commit unrelated dirty files (`.serena/` is expected to be dirty and must stay uncommitted).

---

### Task 2: Renderer integration

**Files:**
- Modify: `lua/nyan/config.lua:1-30` (annotation block and `M.defaults`)
- Modify: `lua/nyan/renderers/space.lua:1-38` (requires, characters, priority table), `:64-76` (`setup_highlights`), `:108-121` (marker collection in `render`)
- Test: `tests/nyan/renderers/space_spec.lua`

**Interfaces:**
- Consumes: `nyan.providers.search` — `M.set_live(pattern)`, `M.clear_live()`, `M.get(bufnr)`, `M.invalidate_all()` from Task 1.
- Produces:
  - `config.get().search` — boolean, default `true`
  - Highlight group `NyanSearch`, linked to `Search`
  - `PRIORITY.SEARCH = 0` in `renderers/space.lua`, the lowest number and therefore the winning priority

- [ ] **Step 1: Write the failing test**

Append these two `describe` blocks to `tests/nyan/renderers/space_spec.lua`, immediately before the final `end)` on line 142. Also add the require at the top of the file, after line 2 (`local config = require("nyan.config")`):

```lua
local search = require("nyan.providers.search")
```

The new blocks:

```lua
  describe("search markers", function()
    before_each(function()
      search.clear_live()
      search.invalidate_all()
      vim.o.hlsearch = true
      vim.o.ignorecase = false
      vim.o.smartcase = false
      vim.v.hlsearch = 0
      vim.fn.setreg("/", "")
    end)

    after_each(function()
      search.clear_live()
      search.invalidate_all()
    end)

    it("renders a search marker for a matching line", function()
      -- Line 50 is well away from the ship at line 1 / cell 0.
      vim.api.nvim_buf_set_lines(buf, 49, 50, false, { "needle" })
      search.set_live("needle")

      local result = space.render()
      assert.is_truthy(result:find("◆"))
    end)

    it("renders no search marker when nothing matches", function()
      search.set_live("nosuchtext")

      local result = space.render()
      assert.is_nil(result:find("◆"))
    end)

    it("search beats an error diagnostic in the same cell", function()
      vim.api.nvim_buf_set_lines(buf, 49, 50, false, { "needle" })
      search.set_live("needle")
      local ns = vim.api.nvim_create_namespace("test_search_priority")
      vim.diagnostic.set(ns, buf, {
        { lnum = 49, col = 0, message = "err", severity = vim.diagnostic.severity.ERROR },
      })

      local result = space.render()
      assert.is_truthy(result:find("◆"))
      assert.is_nil(result:find("✕"))
    end)

    it("ship still beats a search marker in the same cell", function()
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "needle" })
      search.set_live("needle")

      local result = space.render()
      local plain = result:gsub("%%#[^#]+#", ""):gsub("%%*", "")
      assert.equals("▷", plain:sub(2, 4)) -- ▷ is multi-byte
    end)

    it("renders no search marker when search is disabled", function()
      config.setup({ renderer = "space", width = 22, search = false })
      vim.api.nvim_buf_set_lines(buf, 49, 50, false, { "needle" })
      search.set_live("needle")

      local result = space.render()
      assert.is_nil(result:find("◆"))
    end)
  end)

  describe("setup_highlights", function()
    it("defines NyanSearch", function()
      space.setup_highlights()
      local hl = vim.api.nvim_get_hl(0, { name = "NyanSearch" })
      assert.is_not.same({}, hl)
    end)
  end)
```

Add this to `tests/nyan/config_spec.lua`, inside the existing `describe("defaults", ...)` block:

```lua
    it("has search markers enabled by default", function()
      assert.is_true(config.get().search)
    end)
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/nyan/renderers/space_spec.lua"
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/nyan/config_spec.lua"
```

Expected: the space spec reports `Failed : 3` and the config spec reports `Failed : 1`.

The three space failures are "renders a search marker", "search beats an error diagnostic", and "defines NyanSearch". The other three new cases assert the *absence* of a `◆` or the ship winning, so they pass vacuously before the feature exists — that is expected, not a sign the test is wrong.

- [ ] **Step 3: Add the config field**

In `lua/nyan/config.lua`, add this line to the `---@class NyanConfig` annotation block, after the `---@field transparent` line:

```lua
---@field search boolean Show search-hit markers on the space minimap
```

And add this key to `M.defaults`, after `transparent = false,`:

```lua
  search = true,
```

- [ ] **Step 4: Wire the provider into the renderer**

In `lua/nyan/renderers/space.lua`, add the require after line 4 (`local git_provider = require("nyan.providers.git")`):

```lua
local search_provider = require("nyan.providers.search")
```

Add the character constant after the `local TRAIL = "·"` line:

```lua
local SEARCH = "◆"
```

Add `SEARCH = 0` to the `PRIORITY` table, as its first entry:

```lua
-- Priority values (lower = higher priority)
local PRIORITY = {
  SEARCH = 0,
  [vim.diagnostic.severity.ERROR] = 1,
  [vim.diagnostic.severity.WARN] = 2,
  GIT = 3,
  [vim.diagnostic.severity.INFO] = 4,
  [vim.diagnostic.severity.HINT] = 5,
}
```

Add the highlight group to `M.setup_highlights`, after the `NyanBracket` line:

```lua
  vim.api.nvim_set_hl(0, "NyanSearch", { link = "Search", default = true })
```

Add the marker loop in `M.render`, immediately after the git changes loop and before the `-- Build output` comment:

```lua
  -- Search hits
  if cfg.search then
    for _, s in ipairs(search_provider.get(bufnr)) do
      local cell = M.map_to_cell(s.line, total_lines, available_width)
      M.place_marker(markers, cell, {
        char = SEARCH,
        hl = "NyanSearch",
        priority = PRIORITY.SEARCH,
      })
    end
  end
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/nyan/renderers/space_spec.lua"
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/nyan/config_spec.lua"
```

Expected: both report `Failed : 0`, `Errors : 0`.

- [ ] **Step 6: Run lint and the full suite**

```bash
make lint && make lint-luacheck && make test
```

Expected: clean lint, full suite passes.

- [ ] **Step 7: Commit**

```bash
but diff
but commit -b feat/search-markers -m "feat(space): draw search hits as top-priority minimap markers" <file-ids>
```

---

### Task 3: Live command-line wiring and documentation

**Files:**
- Modify: `lua/nyan/init.lua:99-123` (the `cfg.renderer == "space"` autocommand branch)
- Modify: `README.md:7-15` (space theme section), `:65-83` (configuration block), `:85-101` (highlight table)
- Test: `tests/nyan/nyan_spec.lua`

**Interfaces:**
- Consumes: `nyan.providers.search` — `M.set_live(pattern)`, `M.clear_live()` from Task 1; `config.get().search` from Task 2.
- Produces: `CmdlineChanged` and `CmdlineLeave` autocommands in the `NyanNvim` augroup, registered only when `cfg.renderer == "space"` and `cfg.search` is true.

- [ ] **Step 1: Write the failing test**

Append this `describe` block to `tests/nyan/nyan_spec.lua`, after the existing `describe("space renderer integration", ...)` block at the end of the file:

```lua
describe("search command-line wiring", function()
  local orig_getcmdtype, orig_getcmdline

  before_each(function()
    orig_getcmdtype = vim.fn.getcmdtype
    orig_getcmdline = vim.fn.getcmdline
    require("nyan.providers.search").clear_live()
  end)

  after_each(function()
    vim.fn.getcmdtype = orig_getcmdtype
    vim.fn.getcmdline = orig_getcmdline
    require("nyan.providers.search").clear_live()
  end)

  it("registers cmdline autocommands for the space renderer", function()
    require("nyan").setup({ renderer = "space" })

    local changed = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "CmdlineChanged" })
    local left = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "CmdlineLeave" })
    assert.is_true(#changed > 0)
    assert.is_true(#left > 0)
  end)

  it("registers no cmdline autocommands when search is disabled", function()
    require("nyan").setup({ renderer = "space", search = false })

    local changed = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "CmdlineChanged" })
    assert.equals(0, #changed)
  end)

  it("pushes the typed pattern into the provider while searching", function()
    require("nyan").setup({ renderer = "space" })
    local search = require("nyan.providers.search")
    search.invalidate_all()

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha", "needle", "gamma" })

    vim.fn.getcmdtype = function()
      return "/"
    end
    vim.fn.getcmdline = function()
      return "needle"
    end
    vim.api.nvim_exec_autocmds("CmdlineChanged", { group = "NyanNvim" })

    local result = search.get(buf)
    assert.equals(1, #result)
    assert.equals(2, result[1].line)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("ignores non-search command lines", function()
    require("nyan").setup({ renderer = "space" })
    local search = require("nyan.providers.search")
    search.invalidate_all()
    vim.o.hlsearch = true
    vim.v.hlsearch = 0

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha", "needle", "gamma" })

    vim.fn.getcmdtype = function()
      return ":"
    end
    vim.fn.getcmdline = function()
      return "needle"
    end
    vim.api.nvim_exec_autocmds("CmdlineChanged", { group = "NyanNvim" })

    -- No live pattern was set, and hlsearch is off, so nothing is marked.
    assert.same({}, search.get(buf))

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("clears the live pattern when the command line closes", function()
    require("nyan").setup({ renderer = "space" })
    local search = require("nyan.providers.search")
    search.invalidate_all()
    vim.o.hlsearch = true
    vim.v.hlsearch = 0

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha", "needle", "gamma" })

    search.set_live("needle")
    assert.equals(1, #search.get(buf))

    vim.api.nvim_exec_autocmds("CmdlineLeave", { group = "NyanNvim" })
    assert.same({}, search.get(buf))

    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/nyan/nyan_spec.lua"
```

Expected: `Failed : 3` — "registers cmdline autocommands", "pushes the typed pattern into the provider", and "clears the live pattern when the command line closes".

The other two cases assert that *nothing* happens, so they pass vacuously before the autocommands exist. That is expected.

- [ ] **Step 3: Write the implementation**

In `lua/nyan/init.lua`, add this helper immediately above `local function setup_autocommands()` (line 62):

```lua
--- Repaint the statusline, including while the command line is open.
--- A plain `redrawstatus` does not repaint during command-line editing, which
--- is exactly when live search markers need to appear.
local function redraw_statusline()
  if vim.api.nvim__redraw then
    vim.api.nvim__redraw({ statusline = true })
  else
    vim.cmd("redraw")
  end
end
```

Then, inside the `if cfg.renderer == "space" then` block, after the existing `BufWritePost`/`BufEnter`/`FocusGained` autocommand and before the closing `end`, add:

```lua
    if cfg.search then
      local search_provider = require("nyan.providers.search")

      -- Live-update markers as the search pattern is typed. getcmdline() is
      -- only meaningful while the command line is open, so the value is pushed
      -- into the provider here rather than pulled during statusline redraws.
      vim.api.nvim_create_autocmd("CmdlineChanged", {
        group = augroup,
        callback = function()
          local cmdtype = vim.fn.getcmdtype()
          if cmdtype == "/" or cmdtype == "?" then
            search_provider.set_live(vim.fn.getcmdline())
            redraw_statusline()
          end
        end,
      })

      vim.api.nvim_create_autocmd("CmdlineLeave", {
        group = augroup,
        callback = function()
          search_provider.clear_live()
          redraw_statusline()
        end,
      })
    end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/nyan/nyan_spec.lua"
```

Expected: `Failed : 0`, `Errors : 0`.

- [ ] **Step 5: Update the README**

In `README.md`, in the space theme section, replace the line beginning "The space theme turns your statusline into a minimap" (line 13) with:

```markdown
The space theme turns your statusline into a minimap of the current buffer. The ship `▷` shows your cursor position, diagnostic markers `✕` show LSP errors/warnings at their proportional file location, git change markers `│` show where hunks are, and search markers `◆` show where the current search pattern hits. Colours distinguish severity and change type — you get a spatial overview of your file's health without leaving your code.

Search markers update live as you type in `/` or `?`, so you can see where a pattern lands before committing to it, and they clear with `:noh`.
```

In the configuration block, add this line after `debug = false,`:

```lua
  search = true,               -- Show search-hit markers (space renderer)
```

In the Space Theme Highlights table, add this row after the `NyanBracket` row:

```markdown
| `NyanSearch` | `Search` | Search hits `◆` |
```

Do not touch `doc/nyan.txt` — panvimdoc regenerates it from `README.md` at release time.

- [ ] **Step 6: Run lint and the full suite**

```bash
make lint && make lint-luacheck && make test
```

Expected: clean lint, full suite passes.

- [ ] **Step 7: Commit**

```bash
but diff
but commit -b feat/search-markers -m "feat(space): update search markers live while typing a pattern" <file-ids>
```

---

### Task 4: Close the config and init coverage gaps

**Files:**
- Test: `tests/nyan/config_spec.lua`
- Test: `tests/nyan/nyan_spec.lua`

**Interfaces:**
- Consumes: `nyan.config` (`M.setup`, `M.get`, `M.log`), `nyan` (`M.setup`, `M.get`) — all pre-existing.
- Produces: nothing consumed by other tasks.

This task adds no production code. It exists because `config.lua` sat at 63% and `init.lua` at 46% line coverage before this feature, and the uncovered branches are genuinely reachable ones — the debug logging path and the setup wiring — not the Kitty graphics code that cannot run headless.

- [ ] **Step 1: Write the config tests**

Replace the existing `describe("log", ...)` block at the end of `tests/nyan/config_spec.lua` with:

```lua
  describe("log", function()
    local notifications
    local orig_notify

    before_each(function()
      notifications = {}
      orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
    end)

    after_each(function()
      vim.notify = orig_notify
    end)

    it("does nothing when debug is false", function()
      config.setup({ debug = false })
      config.log("test message")
      assert.equals(0, #notifications)
    end)

    it("notifies with a prefix when debug is true", function()
      config.setup({ debug = true })
      config.log("hello")

      assert.equals(1, #notifications)
      assert.equals("[nyan.nvim] hello", notifications[1].msg)
      assert.equals(vim.log.levels.DEBUG, notifications[1].level)
    end)

    it("appends inspected values when extra arguments are given", function()
      config.setup({ debug = true })
      config.log("count:", 42)

      assert.equals(1, #notifications)
      assert.equals("[nyan.nvim] count: 42", notifications[1].msg)
    end)

    it("inspects table arguments", function()
      config.setup({ debug = true })
      config.log("cfg:", { a = 1 })

      assert.is_truthy(notifications[1].msg:find("a = 1", 1, true))
    end)
  end)
```

- [ ] **Step 2: Write the init tests**

Append this `describe` block to `tests/nyan/nyan_spec.lua`, after the block added in Task 3:

```lua
describe("setup wiring", function()
  it("bails out and notifies on Neovim older than 0.10", function()
    local orig_has = vim.fn.has
    local orig_notify = vim.notify
    local notified

    vim.fn.has = function(feature)
      if feature == "nvim-0.10" then
        return 0
      end
      return orig_has(feature)
    end
    vim.notify = function(msg, level)
      notified = { msg = msg, level = level }
    end

    require("nyan").setup({ renderer = "space" })

    vim.fn.has = orig_has
    vim.notify = orig_notify

    assert.is_truthy(notified)
    assert.equals("nyan.nvim requires Neovim 0.10 or later", notified.msg)
    assert.equals(vim.log.levels.ERROR, notified.level)
  end)

  it("registers the three user commands", function()
    require("nyan").setup({ renderer = "space" })
    local commands = vim.api.nvim_get_commands({})

    assert.is_truthy(commands.NyanStart)
    assert.is_truthy(commands.NyanStop)
    assert.is_truthy(commands.NyanToggle)
  end)

  it("wires diagnostic and git autocommands for the space renderer", function()
    require("nyan").setup({ renderer = "space" })

    local diag = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "DiagnosticChanged" })
    local write = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "BufWritePost" })
    assert.is_true(#diag > 0)
    assert.is_true(#write > 0)
  end)

  it("wires focus and exit autocommands for the nyan renderer", function()
    -- The nyan branch calls load_sprites(), which transmits real PNGs to stdout
    -- when kitty.is_supported() is true. Neutralise the terminal detection so
    -- the test does not spray graphics escape sequences into the test output
    -- for anyone running the suite inside Kitty or Ghostty.
    local saved = { vim.env.TERM, vim.env.TERM_PROGRAM, vim.env.KITTY_WINDOW_ID }
    vim.env.TERM = "dumb"
    vim.env.TERM_PROGRAM = ""
    vim.env.KITTY_WINDOW_ID = nil

    require("nyan").setup({ renderer = "nyan", animation = { enabled = false } })

    vim.env.TERM, vim.env.TERM_PROGRAM, vim.env.KITTY_WINDOW_ID = saved[1], saved[2], saved[3]

    local leave = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "VimLeavePre" })
    local diag = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "DiagnosticChanged" })
    assert.is_true(#leave > 0)
    -- The nyan branch must not install the space renderer's autocommands.
    assert.equals(0, #diag)
  end)

  it("always wires the ColorScheme autocommand", function()
    require("nyan").setup({ renderer = "space" })
    local cs = vim.api.nvim_get_autocmds({ group = "NyanNvim", event = "ColorScheme" })
    assert.is_true(#cs > 0)
  end)
end)
```

Note: `setup_autocommands` calls `nvim_create_augroup("NyanNvim", { clear = true })`, so each `setup()` call wipes the previous run's autocommands. That is what makes the "nyan renderer installs no `DiagnosticChanged`" assertion meaningful rather than order-dependent.

Because the last test in this block leaves the `space` renderer configured, and `nyan_spec.lua` runs its blocks in file order, put this block **last** in the file so it cannot disturb the Task 3 tests.

- [ ] **Step 3: Run the tests to verify they pass**

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/nyan/config_spec.lua"
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/nyan/nyan_spec.lua"
```

Expected: both report `Failed : 0`, `Errors : 0`. These tests describe existing behaviour, so they should pass on the first run — if one fails, the assertion is wrong, not the production code. Fix the test.

- [ ] **Step 4: Confirm coverage improved**

```bash
make coverage
```

Expected: the summary shows `lua/nyan/config.lua` above 90%, `lua/nyan/init.lua` above 60%, `lua/nyan/providers/search.lua` above 90%, and the total above the previous 80.24%.

If `make coverage` reports `luacov not found`, run `make coverage-deps` once first. If luarocks is unavailable on this machine, skip this step and note it — it is a reporting step, not a correctness gate.

- [ ] **Step 5: Run lint and the full suite**

```bash
make lint && make lint-luacheck && make test
```

Expected: clean lint, full suite passes.

- [ ] **Step 6: Commit**

```bash
but diff
but commit -b feat/search-markers -m "test: cover config logging and setup wiring branches" <file-ids>
```

---

## Definition of Done

- [ ] `make ci` passes (stylua + luacheck + full test suite).
- [ ] `lua/nyan/providers/search.lua` exists and is covered by `tests/nyan/providers/search_spec.lua`.
- [ ] Typing `/pattern` in a real Neovim session updates the minimap markers before pressing `<CR>`; `:noh` clears them.
- [ ] `require("nyan").setup({ search = false })` renders no `◆` and registers no command-line autocommands.
- [ ] `README.md` documents the marker, the `search` option, and the `NyanSearch` highlight group.
- [ ] `doc/nyan.txt` is untouched — it regenerates from the README at release.
