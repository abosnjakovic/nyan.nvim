# nyan.nvim

<!-- Image placeholder: user will add later -->

Your statusline deserves a rainbow. nyan.nvim brings the iconic Nyan Cat to Neovim, complete with animated frames and a rainbow trail that grows as you scroll through your code.

## Features

nyan.nvim uses the Kitty Graphics Protocol to display actual animated pixel art in your terminal. For terminals that don't support it, there's a colourful ASCII fallback so no one misses out on the fun.

The rainbow trail length shows your scroll position in the buffer — watch it grow as you venture deeper into your code. Animation runs at 6 fps by default and automatically pauses when Neovim loses focus to save your CPU for more important things (like compiling).

## Requirements

- Neovim 0.10+
- For graphics mode: Kitty terminal (or compatible) that supports the Kitty Graphics Protocol
- For the best experience: a mass of code to scroll through

## Installation

Using lazy.nvim:

```lua
{
  "your-username/nyan.nvim",
  config = true,
}
```

Using packer.nvim:

```lua
use {
  "your-username/nyan.nvim",
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

## Commands

- `:NyanStart` — Start the animation
- `:NyanStop` — Stop the animation
- `:NyanToggle` — Toggle animation on/off

## Configuration

```lua
require("nyan").setup({
  width = 20,              -- Total component width in cells
  animation = {
    enabled = true,        -- Enable animation
    fps = 6,               -- Frames per second
  },
  min_buffer_lines = 10,   -- Hide in tiny buffers
  fallback = "ascii",      -- "ascii" or "none" when graphics unavailable
  debug = false,           -- Enable debug logging
})
```

## API

- `require("nyan").get()` — Returns the statusline component string
- `require("nyan").should_display()` — Returns true if component should show
- `require("nyan").get_percentage()` — Returns scroll position (0-100)
- `require("nyan").is_animating()` — Check if animation is running
- `require("nyan").is_graphics_mode()` — Check if using Kitty graphics
- `require("nyan").start()` / `stop()` / `toggle()` — Control animation

## Credits

Inspired by the eternal loop of Nyan Cat and the Emacs nyan-mode https://github.com/TeMPOraL/nyan-mode
