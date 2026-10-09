# Review: Chaptarr server service

Spec: `.github/docs/subagent_docs/chaptarr_spec.md`

## Files changed
- `modules/server/chaptarr.nix` (new)
- `modules/server/default.nix`, `template/server-services.nix`, `justfile`
- `.github/workflows/update-container-images-weekly-wednesday.yml`

## Checks run
| Check | Result |
|---|---|
| `nix eval` of the enabled container/tmpfiles/unit/backup/firewall attrs (server-amd, `path:` ref) | PASS — image `chaptarr/chaptarr:0.9.965`, `8789:8789`, `/config` + `/data`, PUID/PGID/UMASK/TZ, `RequiresMountsFor` honours `mediaMounts`, backup path = dataDir only |
| toplevel drvPath, desktop-amd / stateless-amd (module imported by neither; default config) | PASS |
| toplevel drvPath, server-amd / headless-server-amd with `chaptarr.enable = true` (hostId stubbed) | PASS |
| toplevel drvPath, server-amd / headless-server-amd, unmodified | FAIL — `networking.hostId` assertion from this host's /etc/nixos state; independent of the change (module is `mkIf cfg.enable`, off by default; identical failure with it disabled) |
| `just --summary` parses | PASS |
| Workflow YAML | not parsed (no yaml module available); change is one array line copied from the sportarr entry |
| `git ls-files hardware-configuration.nix` | empty — PASS |
| `system.stateVersion` | untouched |
| Port 8789 collision | none in repo |

## Review notes
- Matches the sportarr/listenarr shape; no `mkIf` role gating; only `cfg.enable`.
- Image pinned and covered by the weekly bump workflow (regex excludes the
  floating `0.9`/`latest` tags).
- Not verified (no network access to a running instance): that `UMASK=002` and
  `/data` as the single parent behave as the third-party guides describe.
- Unrelated and left alone: `bookshelf`, `listenarr`, `sportarr`, `tdarr` and
  `mediamanager` are absent from the justfile service tables (the gap fixed for
  wishlist in f937340).

## Result
PASS pending Phase 6 (preflight needs the new files staged so the flake sees them).
