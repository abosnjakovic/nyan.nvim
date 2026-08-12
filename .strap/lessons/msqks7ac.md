+++
id = "msqks7ac"
tags = ["lua", "nvim", "debugger"]
confidence = 0.6
helped = 0
harmed = 0
created = "2026-08-12T21:02:24.228836Z"
last_confirmed = "2026-08-12T21:02:24.228836Z"
+++

no lua adapter exists for mcp-debugger (strap debug); plugin lua runs inside nvim anyway — debug via the 2s plenary suite plus nvim --headless -c 'lua ...' state dumps; OSV via a generic-DAP MCP tool is the upgrade path if step-debugging ever matters
