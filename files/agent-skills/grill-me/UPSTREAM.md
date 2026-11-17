# grill-me: upstream

- Source: https://github.com/mattpocock/skills/tree/main/skills/productivity/grill-me
- Commit: `5863806dd4e15c63174bee4e7515a4256792ecfa` (2026-11-12)
- License: MIT, Copyright (c) 2026 Matt Pocock. The license text is in `LICENSE` next to this file.
- Local changes: none. Both files are byte-for-byte copies.

`grill-me` only tells the agent to call the `grilling` skill, which does the interview. `grilling` is copied
next to it in `files/agent-skills/grilling/`; without it this skill does nothing. `agents/openai.yaml` is
Codex interface metadata (name and "no implicit invocation").
