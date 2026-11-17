# sol-loop: upstream

- Source: https://github.com/t3dotgg/tstack/tree/main/skills/sol-loop
- Commit: `11e37a74d0a6868c121cd0910ab2b3bd9873b92a` (2026-11-11, "feat(council): act on results as they arrive")
- License: MIT, Copyright (c) 2026 Theo Browne. The license text is in `LICENSE` next to this file.
- Local changes: none. `SKILL.md` is a byte-for-byte copy of upstream.

The upstream skill is a single file; there are no scripts, references or assets.

## Things to know

- It tells the agent to run read-only git (`git status`, `git fetch origin`, `git merge-base`, `git diff`)
  and `gh pr view`.
- It uses T3 Code tools (`orchestrator_capabilities`, `delegate_task`) and an OpenAI "Sol" model, and sends
  the diff to that model. Outside T3 Code it reports that it has no route to Sol.
- It says to push only when the user asks. In this repo `CLAUDE.md` forbids `git push`, and that rule wins.
- It only runs when the user says "sol loop".

## Updating

Copy `skills/sol-loop/SKILL.md` and `LICENSE` from a fresh clone of tstack, read the diff, then update the
commit above.
