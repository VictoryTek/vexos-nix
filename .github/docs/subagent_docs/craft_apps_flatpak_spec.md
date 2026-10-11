# Craft apps (Wordcraft, GridCraft, PdfCraft, PhotoCraft) — Flatpak bundles on the desktop role

## 1. Request

Add Wordcraft (and, per user selection, GridCraft, PdfCraft and PhotoCraft — the
storytold "Crafting Apps") to the **desktop** role. Upstream ships them only as
`.flatpak` bundles attached to GitHub releases. Wordcraft/GridCraft/PdfCraft go in
the GNOME app grid **Office** folder; PhotoCraft goes in a folder together with
PhotoGIMP. The user does **not** want to bump versions by hand (alpha apps, release
every 1–2 days) but liked the pinned/reproducible approach.

## 2. Current state

- `modules/flatpak.nix` installs apps only as `flatpak install flathub <id>` from the
  `flathub` remote, once per app-list hash. A bundle-only app ID in `extraApps` would
  fail every boot and keep the stamp unwritten.
- `modules/flatpak-desktop.nix` sets `vexos.flatpak.extraApps` for the desktop role.
- `modules/gnome-flatpak-install.nix` is the precedent for a second, separate
  flatpak install service (`after flatpak-install-apps`, `requires flatpak-add-flathub`).
- Desktop app-grid folders are defined in **two** places:
  - `modules/gnome-desktop.nix` — system dconf defaults (also what `just reset-defaults` falls back to)
  - `home-desktop.nix` — first-run user dconf write guarded by stamp `.dconf-app-folders-initialized-v5`
- PhotoGIMP's launcher is `org.gimp.GIMP.desktop` (renamed "PhotoGIMP" by `home/photogimp.nix`);
  it is currently in no folder.
- Pinned hand-maintained packages with a scheduled bump workflow already exist:
  `pkgs/brave-origin` + `update-brave-origin-weekly-thursday.yml`, `pkgs/tmog` +
  `update-tmog-weekly-friday.yml` (fetch → rewrite pin → build gate → commit to main).

## 3. Verified upstream facts (2026-10-11)

| App | Latest | App ID | Runtime | Size |
|---|---|---|---|---|
| wordcraft | v0.5.0 | `ai.storyteller.wordcraft` | freedesktop 25.08 | 66 MB |
| gridcraft | v0.5.0 | `ai.storyteller.gridcraft` | freedesktop 25.08 | 12 MB |
| pdfcraft | v0.6.0 | `ai.storyteller.pdfcraft` | freedesktop 25.08 | 62 MB |
| photocraft | v0.7.0 | `ai.storyteller.photocraft` | freedesktop **26.08** | 57 MB |

- Asset name: `<name>-<ver>-linux-x86_64.flatpak` at
  `https://github.com/storytold/<name>/releases/download/v<ver>/…`. Release also has `SHA256SUMS.txt`.
- Bundles embed `runtime-repo = https://dl.flathub.org/repo/flathub.flatpakrepo`; both
  runtimes exist on Flathub (`flatpak remote-info` verified) and are already installed on the dev host.
- Bundles carry no update URL (`<name>-origin` remote has none) → `flatpak update` cannot refresh them.
- Empirically tested in a throwaway `FLATPAK_USER_DIR`:
  - installing a **newer** bundle over an installed one upgrades in place (0.4.0 → 0.5.0 ✔)
  - installing the **same** version again exits non-zero: `… already installed`
  - exported launcher is `<app-id>.desktop`, `Categories=Office;WordProcessor;` for Wordcraft
- License of Wordcraft: MIT OR Apache-2.0.

## 4. Design

Pinned + auto-bumped (reproducible, no manual work):

1. **`pkgs/craft-apps/pins.json`** — `{ <name>: { version, hash } }` (SRI sha256).
2. **`pkgs/craft-apps/default.nix`** — reads the JSON, returns
   `{ <name> = { appId; version; bundle = fetchurl {…}; }; }`. Exposed as
   `pkgs.vexos.craft-apps` in `pkgs/default.nix`.
3. **`modules/flatpak-bundles.nix`** (new, imported by `configuration-desktop.nix`) —
   declares `vexos.flatpak.bundles` (list of `{ id; version; src; }`) and a oneshot
   `flatpak-install-bundles.service`:
   - stamp `/var/lib/flatpak/.bundles-installed-<hash of id@version list>` → a bumped
     pin changes the hash, the service re-runs and upgrades in place
   - `flatpak install --system --noninteractive --assumeyes --bundle <store path>`
   - exit "already installed" is treated as success (same-commit reinstall), any other
     failure leaves the stamp unwritten, writes a failure timestamp, calls `vexos-notify`
     (same pattern as `flatpak.nix`), and never exits non-zero
   - guarded by `config.services.flatpak.enable && cfg.bundles != []` (precedent: `gnome-flatpak-install.nix`)
4. **`modules/flatpak-desktop.nix`** — sets `vexos.flatpak.bundles` from `pkgs.vexos.craft-apps`.
5. **Folders** (`modules/gnome-desktop.nix` + `home-desktop.nix`):
   - Office += `ai.storyteller.wordcraft.desktop`, `ai.storyteller.gridcraft.desktop`, `ai.storyteller.pdfcraft.desktop`
   - new folder **Graphics** = `org.gimp.GIMP.desktop` (PhotoGIMP), `ai.storyteller.photocraft.desktop`
   - `home-desktop.nix` stamp `v5` → `v6` so existing hosts re-apply the layout once
6. **`.github/workflows/update-craft-apps-daily.yml`** — daily 04:30 UTC (offset from the
   03:00 kernels / 04:00 lock jobs). For each key in `pins.json`: resolve
   `releases/latest`, if newer `nix-prefetch-url` + convert to SRI, rewrite JSON with `jq`,
   **gate**: build all bundles via `linkFarm` and assert each file contains
   `app/ai.storyteller.<name>/x86_64/stable` (guards an upstream app-ID rename that would
   silently break the folder entries), then commit to main. Direct-commit style like the
   other pin workflows.

Module Architecture Pattern (Option B): the new behaviour lives in a new
`modules/flatpak-bundles.nix`, imported only by the desktop configuration; no role
`mkIf` added to any shared module. Options guarded by the module's own option are the
documented carve-out.

## 5. Assumptions called out to the user

- Folder name `Graphics` (user asked for "an app grid group with photogimp"; name not specified).
- Desktop role only; htpc/stateless/server unchanged.
- Hosts pick up new versions on the next `just update` / rebuild after the workflow commits
  (same model as brave-origin/tmog), not at runtime.

## 6. Dependencies / Context7

No new flake inputs and no new third-party libraries. Uses nixpkgs `fetchurl`, `flatpak`
CLI, `jq`/`nix-prefetch-url` in CI. Context7 not required (CLAUDE.md: internal change with
no new dependencies). Flatpak bundle behaviour verified empirically (§3) instead.

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Dependency path of `--bundle` (runtime pull from `flathub`) was tested only with `--no-deps` | `runtime-repo` URL equals the configured `flathub` remote; failure leaves stamp unwritten, retried each boot, switch unaffected |
| Upstream publishes a broken alpha build | Same exposure as any `just update`; pin is in git so it can be reverted; gate only checks fetch + app ID |
| Upstream renames the app ID | CI gate refuses to commit |
| Release `latest` ≠ release with x86_64 flatpak | `nix-prefetch-url` 404 fails the step, pin untouched |
| ~190 MB added to desktop closure | Accepted by user (pinned fetchurl chosen); Harmonia cache can serve it |
| Folder stamp bump re-applies layout once and resets manual folder edits | Documented; same practice as previous v4→v5 bump |
| Bundles don't self-update outside repo bumps | Documented limitation of the bundle format |

## 8. Pre-existing issues noted (not touched)

- `modules/gnome-desktop.nix` system defaults have no `3D` folder although `home-desktop.nix` creates it.
- CLAUDE.md says preflight has 9 stages; `scripts/preflight.sh` has 12.
