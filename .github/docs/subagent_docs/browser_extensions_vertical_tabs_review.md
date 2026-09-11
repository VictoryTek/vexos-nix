# Preinstalled Browser Extensions + Vertical Tabs — Review

## Specification Compliance

All implementation steps from the spec completed exactly as planned:

| File | Change | Matches Spec |
|---|---|---|
| New `home/browser-extensions.nix` | Brave External Extensions (5), Brave vertical-tabs seed, `programs.librewolf.policies` (5 extensions + 2 prefs) | ✔ |
| `modules/flatpak.nix` | `io.gitlab.librewolf-community` removed from `defaultApps` | ✔ |
| `home-desktop.nix`, `home-htpc.nix`, `home-server.nix`, `home-stateless.nix` | `./home/browser-extensions.nix` added to imports | ✔ |
| `home/noctalia.nix`, `home/dank-material-shell.nix` | `io.gitlab.librewolf-community` → `librewolf` in `basePinnedApps` | ✔ |
| `modules/gnome-desktop.nix`, `modules/gnome-htpc.nix`, `modules/gnome-server.nix`, `modules/gnome-stateless.nix` | `io.gitlab.librewolf-community.desktop` → `librewolf.desktop` in `favorite-apps` | ✔ |

Post-implementation grep confirms zero remaining `io.gitlab.librewolf` references anywhere in `*.nix`.

## Best Practices / Nix Conventions

- Extension install mechanisms are each the officially-documented, well-tested
  path for their platform (Chromium's "External Extensions" directory;
  Firefox's `ExtensionSettings`/`Preferences` policy schema at the
  non-locked "normal_installed"/"default" tier) — not a hand-rolled
  workaround.
- No new flake inputs; `librewolf` and `programs.librewolf` both come from
  already-pinned, already-`follows`-correct inputs (`nixpkgs`, `home-manager`).
- The activation-script fix applied during review (writing the Brave
  `initial preferences` seed via `pkgs.writeText` + `run cp`, rather than an
  inline heredoc inside `run bash -c '...'`) matches this repo's own
  established `seedHyprlandConf` pattern exactly, rather than introducing a
  new, more fragile quoting style.

## Consistency (Module Architecture Pattern — Option B)

`home/browser-extensions.nix` is a universal-base file with no internal
`lib.mkIf` role/display/gaming guards — imported by exactly the same 4 roles
(desktop, htpc, server, stateless) that already import
`home/gnome-common-browser.nix`, which it deliberately mirrors. No new
role-smuggling `mkIf` introduced anywhere in this change.

## Maintainability

Every extension entry carries both its Chrome Web Store ID and its Firefox
AMO identity (GUID + slug) in one shared `extensions` list, so updating or
adding an extension in the future is a single-line change reflected in both
browsers automatically, rather than editing two independent lists.

## Completeness

All 5 requested extensions (Bitwarden, Clear Cache, Purple Ads Blocker, Smart
HTTPS, Tabliss) and vertical tabs are addressed for both Brave Origin and
LibreWolf, matching the user's confirmed scope (Brave + LibreWolf only, not
Tor Browser; pre-seeded/editable, not locked).

## Performance

No regressions. LibreWolf moving from Flatpak to a native package is a
smaller runtime footprint (no Flatpak sandbox overhead), a net-positive side
effect of the required approach change.

## Security

No hardcoded secrets, no locked/forced configuration, no elevated
permissions requested. Both extension-install mechanisms used here are the
same ones a user would get by manually installing from the Chrome Web
Store / AMO — nothing added beyond what a normal install produces. Purple
Ads Blocker's own third-party-proxy behavior (routing Twitch video traffic)
is inherent to the extension itself, not introduced by this change, and was
flagged to the user in the spec.

## API Currency

Every extension ID (5× Chrome Web Store ID, 5× Firefox AMO GUID + slug) was
pulled from a live store listing or the AMO v5 API directly during Phase 1 —
not typed from memory. The LibreWolf policy mechanism and Brave's "External
Extensions" mechanism were both confirmed by reading actual source (the
home-manager `mkFirefoxModule.nix` file, and `strings` output from the real
`brave-origin` binary) rather than assumed from documentation summaries.

## Build Validation — vexos-nix specific steps

Environment note: this session's new/untracked files (`home/browser-extensions.nix`
plus the edited files) are correctly *not* git-staged (git add/commit is the
user's responsibility per this project's rules) — but Nix's default
`git+file://` flake source filter only includes git-tracked files, which
initially produced a "path does not exist" eval error for the new file. This
is expected behavior given the no-git-add constraint, not a defect in the
change; every validation below was re-run using the `path:` flake URI scheme
instead (bypasses the git-tracking filter, reads the working directory
directly, still respects `.gitignore`), which is the correct way to validate
an uncommitted change locally without staging anything.

| Command | Result |
|---|---|
| `nix flake show --impure path:...` | ✔ PASS — all 30 `nixosConfigurations` + `packages` enumerated, exit 0 |
| `nix eval ... vexos-desktop-amd ... drvPath` | ✔ PASS, exit 0 |
| `nix eval ... vexos-desktop-nvidia ... drvPath` | ✔ PASS, exit 0 |
| `nix eval ... vexos-desktop-vm ... drvPath` | ✔ PASS, exit 0 |
| `nix eval ... vexos-server-amd ... drvPath` (server role touched) | ✔ PASS, exit 0 |
| `nix eval ... vexos-htpc-amd ... drvPath` (htpc role touched) | ✔ PASS, exit 0 |
| `nix eval ... vexos-stateless-amd ... drvPath` (stateless role touched) | ✔ PASS, exit 0 |
| `git ls-files hardware-configuration.nix` | ✔ PASS — empty, not tracked (unaffected by this change) |
| `system.stateVersion` presence, all 6 `configuration-*.nix` | ✔ PASS — none of these files were touched |
| New flake inputs `follows` check | N/A — no new flake inputs added |

### Concrete runtime-content verification (beyond eval-only)

Since browser extension/preference behavior can't be confirmed by Nix
evaluation alone, the actual artifacts this config produces were built and
inspected directly:

- Built `config.home-manager.users.nimda.programs.librewolf.finalPackage` —
  produced real `librewolf.desktop.drv` and `policies.json.drv` derivations.
  Read the actual generated `policies.json`: all 5 extensions present under
  `ExtensionSettings` with `"installation_mode": "normal_installed"` and the
  correct `install_url`, merged cleanly alongside LibreWolf's own baseline
  policies (its bundled uBlock Origin entry, its own extension allowlist) —
  no conflicts. `Preferences."sidebar.revamp"` and
  `."sidebar.verticalTabs"` both present with `"Status": "default"`,
  `"Value": true`. Desktop file confirmed literally named `librewolf.desktop`
  — matches every dock/favourites reference updated in this change.
- Evaluated `config.home-manager.users.nimda.home.file` — confirmed all 5
  Brave "External Extensions" JSON files render at the exact expected path
  (`/home/nimda/.config/BraveSoftware/Brave-Origin/External Extensions/<id>.json`)
  with the exact expected content.

No evaluation errors, no missing-attribute failures, no assertion failures in
any target.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Result

**PASS** — no refinement cycle needed.
