# Search-hit markers for the space renderer

Date: 2026-08-09
Status: Approved, ready for implementation planning

## Summary

Add a third marker source to the space renderer: lines matching the current search
pattern, drawn as `◆` on the minimap. Markers update live as the user types in the
`/` or `?` command line, and persist after `<CR>` for as long as `'hlsearch'` is
active. Search markers take priority over every other marker except the ship.

```
/foo    [ · ◆ · ✕ ◆ ▷ · ◆ · │ · ]
:noh    [ · · · ✕ · ▷ · · · │ · ]
```

Alongside the feature, close the existing coverage gaps in `config.lua` (63%) and
`init.lua` (46%).

## Motivation

The space renderer already turns the statusline into a minimap of buffer health —
diagnostics and git hunks at their proportional file positions. Search hits are the
third thing a developer wants located spatially: after `/pattern`, knowing *where in
the file* the matches cluster is exactly the question a minimap answers, and
Neovim's own search highlighting can only show the matches already on screen.

## Architecture

Three existing pieces already establish the shape, and the feature follows them
rather than inventing anything:

- `providers/git.lua` — a provider is a module exposing `get(bufnr)` returning a
  list of `{ line = N, ... }`, with an internal per-buffer cache and an
  `invalidate(bufnr)` entry point called from an autocommand.
- `renderers/space.lua` — collects markers from each provider, maps line numbers to
  cell indices via `map_to_cell`, and resolves same-cell collisions via
  `place_marker` and a numeric `PRIORITY` table (lower wins).
- `init.lua` — owns all autocommand wiring inside the `NyanNvim` augroup, branching
  on the active renderer.

### Data flow

```
CmdlineChanged (/ or ?)  ──> search.set_live(getcmdline())  ──> redraw
CmdlineLeave             ──> search.clear_live()            ──> redraw
                                      │
statusline evaluation ──> space.render() ──> search.get(bufnr)
                                                  │
                                    live_pattern, else getreg("/") if v:hlsearch
                                                  │
                                    cache hit on (pattern, changedtick)?
                                       yes ──> cached result
                                       no  ──> scan buffer lines, cache, return
```

## Components

### `lua/nyan/providers/search.lua` (new)

Public interface:

| Function | Purpose |
|---|---|
| `M.set_live(pattern)` | Record the pattern being typed in the command line |
| `M.clear_live()` | Forget the live pattern (command line closed) |
| `M.get(bufnr)` | Return `{ line = N }[]` for matching lines |
| `M.invalidate(bufnr)` | Drop one buffer's cached result |
| `M.invalidate_all()` | Drop every cached result |

**Pattern resolution.** The live pattern wins when set. Otherwise the `/` register
is used, but only while `vim.v.hlsearch == 1`. An empty or absent pattern returns
`{}` without touching the buffer.

The live pattern is *pushed in* from the autocommand rather than *pulled* from
`vim.fn.getcmdline()` inside `get()`. `getcmdline()` is only meaningful while the
command line is genuinely active; pushing the value keeps `get()` a plain function
of its inputs, which is also what makes it testable without driving a real command
line.

**Case sensitivity.** `vim.fn.match()` honours `'ignorecase'` but not `'smartcase'`
— smartcase is a property of the search commands, not of `match()`. The one case
where the two disagree is `'ignorecase'` and `'smartcase'` both set with an
uppercase character in the pattern: a real search is case-sensitive there, while
`match()` would be case-insensitive. The provider prepends `\C` in exactly that
case. Uppercase detection strips backslash escapes first (`pattern:gsub("\\.", "")`),
so `\V` and friends do not count as uppercase — the same rule Vim itself applies.

**Scanning.** One `nvim_buf_get_lines` call, then `vim.fn.match(text, pattern) >= 0`
per line. Lines are 1-indexed to match the other providers.

**Invalid patterns are the common path, not an edge case.** Typing `/foo\(` passes
through states that make `match()` throw `E54`. The scan is wrapped in `pcall` and
returns `{}` on failure, so a half-typed regex simply shows no markers.

**Caching.** Keyed on the resolved pattern (before the `\C` prefix is applied) plus
the buffer's `changedtick`, stored per buffer. A single keystroke triggers several
statusline evaluations; the cache collapses those to one scan. Buffer edits bump
`changedtick` and invalidate naturally.

A `M._scan_count` counter, incremented once per actual buffer scan, is exposed for
tests to assert the cache works — the same convention `git.lua` uses when it exposes
`M._parse_hunk_header`. Nothing outside tests reads it.

**Scan cap.** Buffers over 20 000 lines return `{}` rather than scanning. This is a
deliberate ceiling, marked with a `ponytail:` comment naming the upgrade path (a
configurable cap, or an incremental scan) should anyone hit it.

### `lua/nyan/renderers/space.lua` (modified)

- `SEARCH = 0` added to `PRIORITY`, above `ERROR = 1` — search markers win every
  collision. The rationale: search hits are transient and explicitly requested, so
  during a search the minimap becomes a search map, reverting the moment `:noh`
  runs. The ship is drawn after collision resolution and so still wins over search.
- `SEARCH_CHAR = "◆"`, highlight group `NyanSearch`.
- `setup_highlights` gains `NyanSearch` linked to `Search` with `default = true`,
  consistent with every other group in that function.
- `render` gains a third provider loop, guarded by `cfg.search`.

### `lua/nyan/init.lua` (modified)

Inside the existing `cfg.renderer == "space"` branch of `setup_autocommands`, and
only when `cfg.search` is true:

- `CmdlineChanged` — when `vim.fn.getcmdtype()` is `/` or `?`, call
  `search.set_live(vim.fn.getcmdline())` and redraw.
- `CmdlineLeave` — call `search.clear_live()` and redraw.

Both use a local `redraw_statusline()` helper: `vim.api.nvim__redraw({ statusline =
true })` when that function exists, falling back to `vim.cmd("redraw")`. A plain
`redrawstatus` does not repaint while the command line is active, which is precisely
when the live markers need to appear.

### `lua/nyan/config.lua` (modified)

One new field, `search = true`, with a matching `---@field` annotation on
`NyanConfig`. A single boolean rather than a table: there is no second search
setting to group with it yet.

## Error handling

| Condition | Behaviour |
|---|---|
| Invalid regex mid-typing | `pcall` around the scan, return `{}` |
| No pattern / `hlsearch` off | Return `{}` before reading the buffer |
| Invalid or deleted buffer | `pcall` around `nvim_buf_get_lines`, return `{}` |
| Buffer over the line cap | Return `{}` |
| `search = false` | Provider never called from the renderer |

Every failure degrades to "no search markers" — the rest of the minimap keeps
rendering. Nothing in this feature can break the statusline.

## Testing

### `tests/nyan/providers/search_spec.lua` (new)

- Returns `{}` with no pattern set.
- Returns `{}` when `hlsearch` is off but the `/` register holds a pattern.
- Returns matching 1-indexed line numbers when `hlsearch` is on.
- `set_live` overrides the `/` register; `clear_live` restores register behaviour.
- Invalid regex returns `{}` and does not throw.
- Case matrix: `ignorecase` off; `ignorecase` on; `ignorecase` + `smartcase` with a
  lowercase pattern; `ignorecase` + `smartcase` with an uppercase pattern.
- Backslash-escaped uppercase does not trigger the smartcase path.
- Cache: two `get` calls with an unchanged buffer leave `_scan_count` at 1; editing
  the buffer changes the result; `invalidate` and `invalidate_all` force a rescan.
- Buffers over the line cap return `{}`.

### `tests/nyan/renderers/space_spec.lua` (extended)

- `◆` appears when a search pattern matches.
- A search marker beats an error diagnostic in the same cell.
- The ship still beats a search marker in the same cell.
- `search = false` renders no `◆`.

### Coverage gaps closed

- `config.lua` — `log` with no extra arguments, `log` with arguments, `log` while
  `debug = false`, `setup` merging nested tables, `get` returning current options.
- `init.lua` — the Neovim version guard, space-versus-nyan autocommand wiring,
  user commands registered by `setup`, and `get()` returning `""` before `setup`
  runs.

## Documentation

- `README.md` — search markers in the space theme section, `search` in the config
  block, `NyanSearch` in the highlight table.
- `doc/nyan.txt` — matching entries.

## Out of scope

- **Search offsets.** `/foo/e` is taken literally as the pattern `foo/e` and renders
  no markers until the offset is removed. Transient and self-correcting; stripping
  offsets means parsing unescaped separators for little gain.
- **A `live` on/off knob.** The per-keystroke scan is capped and cached. If it
  proves costly on large buffers in practice, split `search` into a table then.
- **Marking the current match distinctly** from the other matches.
