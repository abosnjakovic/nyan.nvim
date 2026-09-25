# nyan.nvim

Neovim plugin (Lua). Plenary test suite, stylua formatting, luacheck static
analysis.

## Build and test

```bash
make test            # plenary suite under headless nvim (~2s)
make lint            # stylua --check
make lint-luacheck   # luacheck static analysis
make format          # apply stylua
make ci              # full local CI parity: lint + luacheck + test
```
