# nyan.nvim

A Neovim statusline component with two rendering modes: a space-themed scroll minimap (default) that shows LSP diagnostics and git changes at a glance, and the classic animated Nyan Cat with a rainbow trail.

<img width="1410" height="954" alt="image" src="https://github.com/user-attachments/assets/e097b2b3-9e6f-4f48-8f1d-f9d9cd064e6f" />

## Space Theme (default)

```
[ · │ · ✕ · ▷ · · · ✕ · · │ · · · · · ]
```

The space theme turns your statusline into a minimap of the current buffer. The ship `▷` shows your cursor position, diagnostic markers `✕` show LSP errors/warnings at their proportional file location, and git change markers `│` show where hunks are. Colours distinguish severity and change type — you get a spatial overview of your file's health without leaving your code.

Git markers work with gitsigns (instant, in-memory) or fall back to `git diff` (no extra plugins required). Diagnostic markers use Neovim's built-in `vim.diagnostic` API.

## Nyan Cat Mode

<img width="3002" height="84" alt="image" src="https://github.com/user-attachments/assets/a714ed70-4041-4f83-b41c-773c753c4437" />

The classic mode uses the Kitty Graphics Protocol to display animated pixel art in your terminal. For terminals that don't support it, there's a colourful ASCII fallback. The rainbow trail length shows your scroll position — watch it grow as you venture deeper into your code.

## Requirements

- Neovim 0.10+
- For Nyan Cat graphics mode: a terminal supporting the Kitty Graphics Protocol (Kitty, Ghostty, etc.)
- For git markers with instant updates: gitsigns.nvim (optional — falls back to `git diff`)

## Installation

Using lazy.nvim:

```lua
{
  "abosnjakovic/nyan.nvim",
  config = true,
}
```

Using packer.nvim:

```lua
use {
  "abosnjakovic/nyan.nvim",
  config = function()
    require("nyan").setup()
  end
}
```

## Usage

Add the component to your statusline. Here's an example with lualine:

```lua
require("lualine").setup({
  sections = {
    lualine_x = {
      { require("nyan").get, cond = require("nyan").should_display },
    },
  },
})
```

## Configuration

```lua
require("nyan").setup({
  renderer = "space",          -- "space" (minimap) or "nyan" (classic cat)
  width = 20,                  -- Total component width in cells
  min_buffer_lines = 10,       -- Hide in tiny buffers
  debug = false,               -- Enable debug logging

  -- Nyan renderer only:
  animation = {
    enabled = true,            -- Enable animation
    fps = 6,                   -- Frames per second
  },
  fallback = "ascii",          -- "ascii" or "none" when graphics unavailable
  theme = "classic",           -- "classic" (bright) or "dark" (muted) rainbow
  transparent = false,         -- Force transparent background on highlights
})
```

### Space Theme Highlights

The space theme links to your existing colourscheme highlight groups by default:

| Group | Links To | Used For |
|---|---|---|
| `NyanShip` | — (bright white) | Ship indicator `▷` |
| `NyanTrail` | `Comment` | Trail dots `·` |
| `NyanBracket` | `Comment` | Brackets `[ ]` |
| `NyanDiagError` | `DiagnosticError` | Error markers `✕` |
| `NyanDiagWarn` | `DiagnosticWarn` | Warning markers `✕` |
| `NyanDiagInfo` | `DiagnosticInfo` | Info markers `✕` |
| `NyanDiagHint` | `DiagnosticHint` | Hint markers `✕` |
| `NyanGitStaged` | `GitSignsAdd` | Staged changes `│` |
| `NyanGitUnstaged` | `GitSignsChange` | Unstaged changes `│` |
| `NyanGitAdded` | `GitSignsAdd` | Added hunks `│` |
| `NyanGitRemoved` | `GitSignsDelete` | Removed hunks `│` |

## Commands

- `:NyanStart` — Start the animation (nyan mode)
- `:NyanStop` — Stop the animation (nyan mode)
- `:NyanToggle` — Toggle animation on/off (nyan mode)

## API

- `require("nyan").get()` — Returns the statusline component string
- `require("nyan").should_display()` — Returns true if component should show
- `require("nyan").get_percentage()` — Returns scroll position (0-100)
- `require("nyan").is_animating()` — Check if animation is running
- `require("nyan").is_graphics_mode()` — Check if using Kitty graphics
- `require("nyan").start()` / `stop()` / `toggle()` — Control animation

## Credits

Inspired by the eternal loop of Nyan Cat and the Emacs nyan-mode https://github.com/TeMPOraL/nyan-mode
