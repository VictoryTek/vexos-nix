# Joplin justfile info messages — review

## Specification compliance

All three branches from the spec were added at the alphabetically-correct
location (adjacent to `jellyfin`/`kavita`, matching file convention):

1. `_info` case (justfile:1381) — `joplin) printf ... Web UI http://<tailnet-host>:22300 (Tailscale-only)`
2. `just status` case (justfile:1511) — `UNITS="docker-joplin-server docker-joplin-db"; URLS="http://localhost:22300"`
3. Post-`just enable` info case (justfile:1913-1919) — services, Web UI,
   About, Login, and baseUrl note.

Matches spec exactly. Diff is 3 additions, 0 deletions, no unrelated lines
touched.

## Best practices / consistency

- Follows the exact `case "$SERVICE" in ...)` / `printf`/`echo` formatting
  used by every neighboring entry (column alignment in the `_info` case,
  `echo "  Label:   value"` in the post-enable case).
- Unit names (`docker-joplin-server`, `docker-joplin-db`) match the
  `virtualisation.oci-containers.containers.*` names declared in
  `modules/server/joplin.nix:150,163` with the `docker-` prefix NixOS's OCI
  container module applies — same convention already used for
  `dockhand`/`stirling-pdf`/`uptime-kuma` entries in this file.
- Port (22300) and Tailscale-only scoping match `modules/server/joplin.nix`
  (`cfg.port` default, `networking.firewall.interfaces.tailscale0`).
- First-login credentials and the `baseUrl` "invalid origin" caveat are
  taken verbatim from the header comment in `modules/server/joplin.nix:23-31`.

## Completeness

No other justfile touchpoint was missing an entry — `_svc joplin` (catalog,
line 1333) and `_server_service_names` (line 1133) already listed joplin
correctly; only the three per-service `case` blocks were gapped.

## Security

No secrets, no new commands, no privilege changes. Text-only `echo`/`printf`
additions.

## Build validation

**Not run in this session — environment limitation, not a skipped step.**
This session is a Windows workstation (`win32`) with no `nix`, `just`, or
`nixos-rebuild` binaries present (verified: `which nix` / `which
nixos-rebuild` both fail; `scripts/preflight.sh` itself documents that it
"must be made executable on the NixOS host" and is not runnable from
Windows). The change is confined to `justfile`, which Nix never evaluates,
so none of the vexos-nix build-validation commands (`nix flake show
--impure`, `nixos-rebuild dry-build`) exercise this code path regardless of
host.

What **was** verified on this machine:
- `git diff -- justfile` — confirmed the diff is exactly the 3 intended
  insertions, nothing else touched.
- `case`/`esac` counts before and after are balanced (14/14) — no structural
  breakage from the sed-based insertions (one required a follow-up fix
  after a literal-newline artifact from `sed a\`; corrected and re-verified).
- `git ls-files hardware-configuration.nix` — empty (not tracked, unrelated
  but checked per repo rule).
- `grep -c stateVersion configuration-*.nix` — 6 (unchanged, file not
  touched).

**Outstanding — user must verify on the actual NixOS/server host:**
```
just enable joplin      # confirm the new Web UI/Login/Note lines print
just info joplin        # confirm the _info line prints
just status joplin      # confirm the two docker-joplin-* units are checked
```

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Consistency | 100% | A |
| Maintainability | 100% | A |
| Security | 100% | A |
| Completeness | 100% | A |
| Build Success | N/A (no Nix eval; runtime `just` check deferred to host) | — |

**Overall Grade: A (100%) — with build/runtime verification deferred to the NixOS host per environment constraints above.**

## Result

**PASS** (Phase 6 preflight cannot be executed in this environment — see
Build validation section; recommend the user run the three `just` commands
above on the server after pulling this change, before the next `just
rebuild`).
