# ui-ux-pro-max: upstream

- Source: https://github.com/nextlevelbuilder/ui-ux-pro-max-skill, folder `.claude/skills/ui-ux-pro-max/`
- Commit: `e59ff376a41f7ca47b7541ad5c116495cbade3ee` (2026-11-16, "feat(design): add optional UberLLM logo provider (#567)"); skill version 2.15.0
- License: MIT, Copyright (c) 2024 Next Level Builder. The license text is in `LICENSE` next to this file.

## Local changes

- `SKILL.md`: every `${CLAUDE_PLUGIN_ROOT}/.claude/skills/ui-ux-pro-max/scripts/search.py` is now
  `/etc/vexos/agent-skills/ui-ux-pro-max/scripts/search.py`. Upstream assumes it is installed as a Claude Code
  plugin; here it is a plain skill, so that variable is not set. This is the only edit.
- Left out (not used when the skill runs): `scripts/tests/`, `scripts/validate_data.py`,
  `data/phosphor-icons-upstream.json`, `data/google-font-licenses.json`, `data/data-provenance.json`,
  `data/catalog-summary.json`.

## Things to know

- The skill runs `python3 scripts/search.py`. The scripts read the local CSVs. They write files only with
  `--persist` (under `design-system/` in `--output-dir`, or in the current directory if none is given) or
  `--preview` (`preview.html` in `--output-dir`, or a temp file if none is given). There are no network calls
  and no subprocesses. The generated `preview.html` links Google Fonts when opened in a browser.
- Needs Python 3 on the host. `modules/development.nix` installs it; a host with only the ai feature may not have it.

## Updating

Copy the same files from a fresh clone, redo the path edit above, read the diff, then update the commit above.
