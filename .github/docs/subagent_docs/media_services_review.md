# Review: MediaManager, Sportarr, Tdarr, Listenarr server services

Spec: `.github/docs/subagent_docs/media_services_spec.md`
Files: `modules/server/{mediamanager,sportarr,tdarr,listenarr}.nix`,
`modules/server/default.nix`, `template/server-services.nix`.

Reviewer note: implementation and review were done by the same agent, inline,
not by separate subagents.

## Build validation (WSL, Nix 2.34.1, scratch copy of the tree)
| Check | Result |
|---|---|
| `nix eval` toplevel drvPath: desktop-{amd,nvidia,vm}, server-amd, headless-server-amd, stateless-amd, htpc-amd | all evaluate |
| `vexos-server-amd` with all four enabled | evaluates; ports 1867, 4545, 8000, 8265, 8266 opened; units `docker-{mediamanager,mediamanager-db,sportarr,listenarr}`, `mediamanager-{network,secrets-init,dump}`, `tdarr-{server,node-local}` exist |
| MediaManager enabled without `adminEmails` | fails with the intended assertion message |
| `scripts/preflight.sh` | exit 0, 10/10 stages (see limitations) |
| `hardware-configuration.nix` tracked | no |
| `system.stateVersion` | no `configuration-*.nix` modified |
| New flake inputs | none |

`nixos-rebuild dry-build` was not run: no NixOS host here. Evaluating the same
toplevel derivation was used instead (CLAUDE.md-sanctioned equivalent).

## Findings
- No CRITICAL issues.
- Spec compliance: matches. One deliberate deviation recorded here: MediaManager
  `userId`/`groupId` options were dropped (upstream has no PUID/PGID and a
  non-root run is unverified), mounts are root-owned.
- Option B: no role-gating `mkIf`; `mkIf cfg.enable` guards on each module's own
  option only (permitted carve-out). `mkMerge` in mediamanager mirrors joplin.
- Security: no plaintext secrets in the repo; MediaManager secrets generated
  0600 in a 0700 directory; preflight 7a flags only a pre-existing
  `vexboard.nix` placeholder.
- Maintainability: header comments state upstream, tag policy and caveats.

## RECOMMENDED / known limitations (not blocking)
1. Listenarr tracks the rolling `canary` tag (no stable tag exists upstream).
2. Preflight stage 2 (dry-build) skipped (no `/etc/nixos/vexos-variant`); stages
   1b, 5b and 5c skipped because `jq` is not installed in WSL; `nixpkgs-fmt` and
   `gitleaks` not installed. None of these reported a failure.
3. Containers were not started; runtime behaviour (MediaManager as root,
   Listenarr mounts, Tdarr node pairing) is untested.
4. New files must be `git add`ed before flake evaluation sees them (preflight
   stage 10 fails otherwise).

## Scores
| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 95% | A |
| Best Practices | 92% | A- |
| Functionality | 85% | B+ (untested at runtime) |
| Code Quality | 93% | A |
| Security | 93% | A |
| Performance | 95% | A |
| Consistency | 95% | A |
| Build Success | 95% | A (eval only, no dry-build) |

**Overall Grade: A- (92%) — PASS**
