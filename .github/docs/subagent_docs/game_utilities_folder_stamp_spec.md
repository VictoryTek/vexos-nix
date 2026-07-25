# Game Utilities app-folder not updating after Discord/Vesktop nixpkgs→Flatpak move

## Current state analysis

- `modules/gaming.nix` correctly declares Discord/Vesktop only as Flatpak apps
  (`vexos.flatpak.managedApps` / `vexos.flatpak.extraApps`), with no nixpkgs
  `environment.systemPackages` entries — verified via repo-wide grep. This part
  of commit `fc9e771` ("fix(gaming): move Discord/Vesktop from nixpkgs to
  Flatpak") is correct and complete.
- `home-desktop.nix` defines a `systemd.user.services.vexos-init-app-folders`
  oneshot service that writes the GNOME app-folders dconf layout exactly once,
  gated by a stamp file:
  `$HOME/.local/share/vexos/.dconf-app-folders-initialized-v3`.
  If the stamp exists, the script exits immediately without touching dconf.
- The "Game Utilities" folder's `apps` list in that script was updated by
  `fc9e771` to use the Flatpak `.desktop` IDs (`dev.vencord.Vesktop.desktop`,
  `com.discordapp.Discord.desktop`) — matching `modules/gnome-desktop.nix`'s
  system dconf defaults, which were updated in the same commit.
- The stamp filename (`-v3`) was **not** bumped in that commit. Git history
  shows this file has bumped the stamp version on every prior content change
  to the app-folders payload (v1→v2 in `c14c639`, v2→v3 in `69815f8`, v3→v4→v3
  in `9741ba3`/`4bc89cf`).

## Problem definition

On any host where `vexos-init-app-folders` already ran and wrote the
`v3` stamp (i.e. any existing/updated system — not a fresh install), the
oneshot service now exits at `[ -f "$STAMP" ] && exit 0` before ever writing
the new Flatpak-based `.desktop` IDs into the user's live dconf database. The
live "Game Utilities" folder therefore still contains whatever IDs were
written the last time the stamp was bumped (pre-Flatpak-migration), and
Discord/Vesktop silently disappear from the folder in the app grid even
though the Nix source is correct.

## Proposed solution

Bump the stamp filename in `home-desktop.nix`'s `vexos-init-app-folders`
service from `.dconf-app-folders-initialized-v3` to
`.dconf-app-folders-initialized-v4`, matching the established pattern. This
forces the oneshot service to re-run once on the next login/rebuild and
rewrite the full app-folders dconf tree (all folders, not just Game
Utilities) with the current, correct payload — after which the new stamp
file prevents further reruns until the payload next changes.

No other files need the bump: `home-htpc.nix`, `home-server.nix`, and
`home-stateless.nix` use the same stamp pattern independently
(`-v2`, unrelated to this change) but do not reference Discord/Vesktop in
their app-folders payload, so their state is unaffected by this bug.

## Implementation steps

1. `home-desktop.nix`: change `STAMP="$HOME/.local/share/vexos/.dconf-app-folders-initialized-v3"`
   to `...-v4` in the `vexos-init-app-folders-desktop` script, and rename the
   `pkgs.writeShellScript` label accordingly if it embeds the version (it does
   not currently — no further change needed there).

## Dependencies

None — no new packages or external libraries involved.

## Risks and mitigations

- Risk: bumping the stamp re-runs the *entire* app-folders dconf write, not
  just the Game Utilities folder. Mitigation: this is intentional and matches
  every prior stamp bump in this file's history — the full payload is
  idempotent and safe to rewrite.
- Risk: user's manual customizations to app-folders (if any) made outside the
  managed lists would be overwritten on next login after this change.
  Mitigation: this is the documented, accepted tradeoff of the existing
  stamp-file design (see comment in `home-htpc.nix`); no behavior change to
  that tradeoff, just triggering it once more as intended.
