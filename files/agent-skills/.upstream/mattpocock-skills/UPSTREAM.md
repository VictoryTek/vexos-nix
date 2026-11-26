# mattpocock-skills: upstream

- Source: https://github.com/mattpocock/skills, folders `skills/engineering/` and `skills/productivity/`
- Commit: `6f7f7831a625f040a8e06a0e7954826b87ce775a` (2026-11-25)
- License: MIT, Copyright (c) 2026 Matt Pocock (`LICENSE` next to this file).
- Local changes: none. Every folder is a byte-for-byte copy of the upstream folder, including `agents/openai.yaml`.

Skills copied, from `skills/engineering/`:

- Requested: grill-with-docs, domain-modeling, to-spec, to-tickets, implement, code-review, retro, tdd,
  setup-matt-pocock-skills.
- Pulled in because a skill calls them with the Skill tool: `codebase-design` (from `tdd`) and, from
  `skills/productivity/`, `writing-for-agents` (from `retro`).

Already vendored separately, with their own `UPSTREAM.md` (commit `5863806`, content identical to this commit):
`grilling` and `grill-me`. `grill-with-docs` calls `grilling`.

Not copied: the other upstream skills. The ones the copied skills only mention conditionally are `triage`,
`wayfinder`, `prototype`, `research`, `pr`, `improve-codebase-architecture`. `setup-matt-pocock-skills` asks whether
`triage` is installed and skips its triage-label section when it is not.

## Things to know

- **Names.** `code-review` has the same name as Claude Code's built-in `/code-review`. Check which one wins when
  you invoke it.
- **Manual-only skills.** `grill-with-docs`, `to-spec`, `to-tickets`, `implement`, `retro` and
  `setup-matt-pocock-skills` set `disable-model-invocation: true`. They only run when you type the command.
- **Setup first.** `to-spec`, `to-tickets` and `code-review` expect the issue tracker settings that
  `/setup-matt-pocock-skills` writes into a repo's `CLAUDE.md`/`AGENTS.md` and `docs/agents/`. Run it once per repo.
- **git rules.** `implement` ends with "Commit your work to the current branch". In this repo `CLAUDE.md` forbids
  `git commit`, and that rule wins.
- **Scripts.** None of the copied skills bundle scripts.

## Updating

Copy the folders from a fresh clone, read the diff, then update the commit above.
