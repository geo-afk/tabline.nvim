# modern-tabline.nvim

A clean, modern, performant buffer tabline for Neovim with smart visibility, icons, and smooth highlighting.

## Features
- Smart buffer visibility based on window width
- File icons via `nvim-web-devicons` or `mini.icons`
- Subtle blended highlights (no harsh contrasts)
- Clickable buffers and close buttons
- Modified indicator
- Overflow indicators (‹ ›)
- Buffer navigation with `<Tab>` / `<S-Tab>`
- Close current buffer with `<A-c>`
- Full health check support

## Installation

### Lazy.nvim
```lua
{
  "yourusername/modern-tabline.nvim",
  config = function()
    require("modern-tabline").setup({
      enabled = true,
      -- optional overrides
      -- separator = "▎",
      -- close = "󰅖",
      -- modified = "●",
    })
  end
}


###Configuration
require("modern-tabline").setup({
  enabled = true,
  separator = "│",
  close = "×",
  modified = "●",
  hide_misc = true,
  min_visible = 3,
  max_visible = 10, -- 0 = unlimited
  style = {
    active_bg_blend = 0.12,
    inactive_fg_blend = 0.5,
    separator_opacity = 0.3,
    padding = "  ",
  },
})

```
