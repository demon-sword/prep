# Ralph — System Design Topic Generator

Headless Cursor Agent loop to generate a full `system-design/<topic>/` bundle.

## Quick start

```bash
# 1. Scaffold topic folder
./ralph-system-design/scaffold.sh slack

# 2. Run loop (one agent iteration per plan item)
./ralph-system-design/loop.sh slack 25

# Or single iteration
./ralph-system-design/once.sh slack

# Optional: pin a model
./ralph-system-design/loop.sh slack 25 --model sonnet-4
```

## What it produces

See `ralph-system-design/spec.md` and `system-design/README.md`.

## Scripts

| Script | Purpose |
|--------|---------|
| `scaffold.sh <topic>` | Create folder, copy assets, initial plan.md |
| `once.sh <topic>` | One Cursor Agent iteration (reference: `pulse/ralph/once.sh`) |
| `loop.sh <topic> [max]` | Repeat until `<promise>COMPLETE</promise>` |
| `gen-plan.sh <topic>` | Parse design-doc sections → answer tasks in plan.md |
| `validate.sh <topic>` | Objective completion gates |
| `scripts/md_to_html.py <topic>` | Convert answers/*.md → answers-html/*.html |

## Agent flags

Same as Pulse: `--print --trust --force --approve-mcps --workspace .`

Env vars:
- `CURSOR_MODEL` — optional; omit for Cursor default (auto)
- `CURSOR_AGENT_TIMEOUT_SEC` — default `2700` (45m)
- `CURSOR_AGENT_OUTPUT_FORMAT` — default `stream-json`

## Logs

`ralph-system-design/.logs/<topic>-iter-*.log`

## Notes

- Agent uses Task/subagents for research-heavy steps (see `prompt.md`)
- No human gate — design doc flows straight into answer generation
- HTML is presentation only (tabs/flashcards via `interactive.js`, no demo widgets)
- Section count derived from design doc, not fixed
