# macism-ime.nvim

Automatically switch the macOS input source according to the Neovim mode, built on top of [macism][1].
Made for Vietnamese typists (Telex/VNI engines such as XKey), but it works with any input source ID, including CJK.

- **Normal / Visual / `:`** → ABC
- **Insert / Replace / Select / Terminal** → the input source you used last
- **`/`, `?` and `:%s/…`** → the Insert input source, so you can search and substitute in your own language
- **Startup** → the current input source is saved; **exit** (and `Ctrl-Z`) → it is restored
- Optional: per-buffer memory, per-filetype input, detecting Vietnamese text near the cursor
- macOS only. On other systems `setup()` does nothing, so shared dotfiles stay safe.

> Status: early version (v0.1). Issues and feedback are welcome.

## Requirements

- macOS, Neovim 0.10+ recommended
- [macism][2]: `brew install laishulu/homebrew/macism`

To get an input source ID, switch to it and run `macism` in a terminal, for example
`com.apple.keylayout.ABC` or `com.codetay.inputmethod.XKey`.

## Installation

[lazy.nvim][3]:

```lua
{
  "drnhat/macism-ime.nvim",
  lazy = false, -- load at startup so the original input source is captured immediately
  config = function()
    require("macism_ime").setup({
      -- see "Configuration"
    })
  end,
}
```

## Configuration

Defaults:

```lua
require("macism_ime").setup({
  normal = "com.apple.keylayout.ABC", -- input source for Normal / Visual / ":"
  remember = true,       -- remember the input source used in the previous Insert session
  scope = "global",      -- "global" or "buffer" (remember per buffer)
  insert_default = nil,  -- input source for the first Insert if nvim was started with ABC
  filetype_input = {},   -- force an input source per filetype, e.g. { markdown = "<id>" }
  detect = {
    enable = false,      -- use `input` when the cursor line contains Vietnamese letters
    input = nil,         -- REQUIRED when enabled, e.g. "com.codetay.inputmethod.XKey"
    pattern = [[...]],   -- Vim regex of Vietnamese letters (see the source for the default)
  },
  macism = nil,          -- path to the macism binary; nil = search PATH, then /opt/homebrew/bin and /usr/local/bin
  wait = nil,            -- ms macism waits after switching to a CJKV input source (nil = macism default, 150ms)
  timeout = 1500,        -- ms; a hung macism is abandoned instead of freezing Neovim
  terminal = true,       -- treat terminal mode as a typing mode
  focus_sync = true,     -- on FocusGained, force `normal` unless typing
  exclude_filetypes = {},-- filetypes that never get the alternative input source
  cmdline_patterns = {   -- ":" commands that restore the Insert input source (Lua patterns)
    "^%s*[%%%d%.%$,;+%-]*s[/#]",  -- :s/  :%s/  :1,5s/
    "^%s*'[<>%a],'[<>%a]s[/#]",   -- :'<,'>s/
  },
  debug = false,         -- log to stdpath("state") .. "/ime.log"
})
```

Input source selection when entering Insert (first match wins):
`detect` → `filetype_input` → per-buffer memory (`scope = "buffer"`) → global memory.

Example for a Vietnamese user who keeps code in English and notes in Vietnamese:

```lua
require("macism_ime").setup({
  scope = "buffer",
  detect = { enable = true, input = "com.codetay.inputmethod.XKey" },
  filetype_input = {
    markdown = "com.codetay.inputmethod.XKey",
    gitcommit = "com.codetay.inputmethod.XKey",
  },
})
```

## Commands

| Command            | Description                                                    |
| ------------------ | -------------------------------------------------------------- |
| `:MacismImeToggle` | Enable / disable automatic switching                           |
| `:MacismImeInfo`   | Show the original, remembered, target and current input source |

## Troubleshooting

- **The first keystrokes after `i` are typed in the old input source**: upgrade macism (`brew upgrade macism`) or increase the wait, e.g. `wait = 150`.
- **"macism not found" when Neovim is launched from a GUI app** (browser editor integrations such as Tridactyl, Alfred, Raycast...): such processes get a minimal `PATH` without Homebrew. The plugin falls back to `/opt/homebrew/bin` and `/usr/local/bin`; for any other location set `macism = "/full/path/to/macism"`.
- **Nothing happens when focusing the window inside tmux**: add `set -g focus-events on` to your tmux config.
- Set `debug = true`, reproduce the problem and check `~/.local/state/nvim/ime.log`.

## Credits

Built on [macism][4] by laishulu. Ideas from
[auto-input-switch.nvim][5],
[vim-barbaric][6] and
[im-select.nvim][7].

## License

MIT

[1]:	https://github.com/laishulu/macism
[2]:	https://github.com/laishulu/macism
[3]:	https://github.com/folke/lazy.nvim
[4]:	https://github.com/laishulu/macism
[5]:	https://github.com/amekusa/auto-input-switch.nvim
[6]:	https://github.com/rlue/vim-barbaric
[7]:	https://github.com/keaising/im-select.nvim