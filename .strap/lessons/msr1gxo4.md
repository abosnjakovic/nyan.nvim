+++
id = "msr1gxo4"
tags = ["lua", "debugging"]
confidence = 0.6
helped = 0
harmed = 0
created = "2026-08-13T04:49:32.020989Z"
last_confirmed = "2026-08-13T04:49:32.020989Z"
+++

strap debug --attach to OSV: 'continue' blocks until the debuggee stops (60s timeout). Trigger nvim activity concurrently — any buffer edit fires the statusline, which calls nyan's space renderer -> position.get_scroll_position, hitting breakpoints in that path for free.
