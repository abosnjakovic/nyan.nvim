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

## Harness

This project uses strap (per-project agent harness). Start tasks with
`strap lesson search "<topic>" --json`; record non-obvious learnings with
`strap lesson add "..." --tag lua --tag nvim`; close the loop with
`strap lesson feedback <id> --helped|--harmed`. See `strap --help`.

The `regression` flow (lint + tests, agent fix on red, `make lint && make test`
as ground truth) runs after each Claude Code session via the Stop hook in
`.claude/settings.json`; run it manually with `strap flow run regression`.
