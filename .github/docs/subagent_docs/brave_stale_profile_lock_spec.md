# Spec — Auto-clear stale Brave profile lock on session start

**Feature name:** `brave_stale_profile_lock`
**Author:** Orchestrating Agent (Phase 1)
**Status:** Draft for Phase 2 implementation
**Chosen approach:** Option A — login-time stale-lock sweep (`systemd.user` service)

---

## 1. Current state analysis

### 1.1 Observed failure

On host `vextop` (role: desktop), launching **Brave Origin** from the GNOME dash
does nothing — no window, no visible error. Reproduced from a terminal under a
scratch Xvfb display:

```
ERROR:chrome/browser/process_singleton_posix.cc:365] The profile appears to be
  in use by another Brave process (8049) on another computer (vexos). Brave has
  locked the profile so that it doesn't get corrupted. ...
ERROR:chrome/browser/ui/dialogs/process_singleton_dialog_linux.cc:93] Cannot
  show profile-in-use dialog: no system dialog tool (zenity, kdialog, xmessage)
  was found.
```

State on disk:

```
~/.config/BraveSoftware/Brave-Origin/SingletonLock  -> vexos-8049
~/.config/BraveSoftware/Brave-Origin/SingletonCookie -> 13547502787573396066
~/.config/BraveSoftware/Brave-Origin/SingletonSocket -> /tmp/org.chromium.Chromium.<x>/SingletonSocket
```

Current `hostname` is `vextop`. `nixpkgs` `brave` was unaffected only because it
had no leftover `SingletonLock`.

### 1.2 Mechanism (Chromium `ProcessSingleton`, POSIX)

- While Brave runs, it creates `SingletonLock` as a **symlink** whose target is
  `"<hostname>-<pid>"`. It is removed on clean shutdown.
- An unclean exit (display-manager restart during `nixos-rebuild switch`, crash,
  power loss) leaves the symlink behind.
- On the next start Brave parses the symlink target, splitting on the last `-`
  into `hostname` + `pid`, then:
  - **`hostname == gethostname()`** → checks whether `pid` is alive; if not, the
    lock is treated as stale, silently replaced, and startup proceeds. *(This
    path already works — it is why stale locks were historically invisible.)*
  - **`hostname != gethostname()`** → assumes the profile lives on shared
    storage in use by a *different* machine, returns `PROFILE_IN_USE`, and asks
    the UI to show an unlock dialog. The `pid` is **not** checked in this path.
- On a NixOS GNOME session there is no `zenity` / `kdialog` / `xmessage`, so
  `ShowProfileInUseError` fails and the process exits `0` with no window.

### 1.3 Why this hit multiple machines "after updating"

`modules/network.nix:130` sets `networking.hostName = lib.mkDefault "vexos"`;
each `hosts/*.nix` overrides it with the real machine name. Any device that ran
Brave at least once while still on the default `vexos` hostname, then was
rebuilt/renamed, now has a `SingletonLock -> vexos-<pid>` that resolves to the
mismatch path on every launch. It is a one-time migration artifact, but nothing
in the repo clears it and a fresh unclean shutdown can reintroduce a
same-hostname stale lock at any time (handled by Brave) — only the cross-host
variant is fatal.

### 1.4 Relevant existing code

| Path | Role |
|------|------|
| `home/gnome-common-browser.nix` | Shared HM addition imported by **exactly** the four roles that install `vexos.brave-origin` (`desktop`, `server`, `htpc`, `stateless`). Currently only sets XDG MIME defaults. |
| `home-desktop.nix`, `home-server.nix`, `home-htpc.nix`, `home-stateless.nix` | Each imports `home/gnome-common-browser.nix` and each **duplicates** a `systemd.user.services.vexos-migrate-dock-brave-origin` oneshot (stamp-file, `After`/`PartOf`/`WantedBy = graphical-session.target`). Precedent for the unit style. |
| `modules/packages-desktop.nix:7-8` | Installs `brave` and `vexos.brave-origin` (system-wide, desktop package set). |
| `pkgs/brave-origin/default.nix` | Pre-built binary package; ships its own `.desktop` (`Exec=$out/bin/brave-origin %U`). |
| `modules/impermanence.nix` | Stateless role: `/home` is tmpfs, fully ephemeral — no lock survives a reboot there, so the sweep is a no-op but harmless. |
| `modules/server/syncthing.nix` | Server role only, `mkEnableOption` (off by default), `dataDir = /home/<user>`, **no declarative folders**. A user could manually configure Syncthing to sync `~/.config/BraveSoftware` between machines — see Risk R1. |

### 1.5 Home Manager systemd.user idiom in this repo

`systemd.user.services.<name>` with attrs `Unit` / `Service` / `Install`
(capitalised, raw systemd keys), `ExecStart = toString (pkgs.writeShellScript
"<name>" '' ... '')`, ordered on `graphical-session.target`. Stamp files live
under `$HOME/.local/share/vexos/`.

---

## 2. Problem definition

Brave (Origin or regular) silently fails to launch whenever a
`SingletonLock` symlink exists whose embedded hostname differs from the current
hostname, because NixOS GNOME sessions have no dialog helper for Chromium's
unlock prompt.

**Goal (verifiable):** After a session login, if
`~/.config/BraveSoftware/<Brave-Origin|Brave-Browser>/SingletonLock` points to a
`"<host>-<pid>"` target with `<host> != $(hostname)` and no Brave process is
running for the user, that `SingletonLock` (plus `SingletonCookie`,
`SingletonSocket`) is removed, so the next Brave launch opens a window.
Same-hostname locks and live sessions are left untouched.

**Non-goals:**
- Do not touch same-hostname stale locks (Brave already handles those).
- Do not add `zenity` (heavier; still interrupts the user; does not prevent).
- Do not change `networking.hostName` behaviour or the installer flow.
- Do not deduplicate the existing `vexos-migrate-dock-brave-origin` services
  (out of scope; separate tech-debt item — note only).

---

## 3. Proposed solution architecture

### 3.1 Placement (Module Architecture Pattern — Option B)

Add the service to **`home/gnome-common-browser.nix`**. That file is the
existing *shared addition* imported by precisely the four roles that ship
`brave-origin`; it already scopes "this machine has Brave" correctly through the
import list. No `lib.mkIf` role guard is introduced. No new file is needed
because a suitable shared addition file already exists and already owns
"Brave-specific user config".

`headless-server` and `vanilla` do not import this file and get nothing — correct
(no browser).

### 3.2 The unit

```nix
systemd.user.services.vexos-brave-clear-stale-lock = {
  Unit = {
    Description = "VexOS: clear stale cross-host Brave profile lock";
    After  = [ "graphical-session.target" ];
    PartOf = [ "graphical-session.target" ];
  };
  Service = {
    Type            = "oneshot";
    RemainAfterExit = true;
    ExecStart = toString (pkgs.writeShellScript "vexos-brave-clear-stale-lock" ''
      set -u
      HOST="$(${pkgs.nettools}/bin/hostname)"     # short hostname, matches Chromium's net::GetHostName default

      # Refuse to touch anything if a Brave process is already running for this user.
      if ${pkgs.procps}/bin/pgrep -u "$UID" -x brave >/dev/null 2>&1; then
        exit 0
      fi

      for profile in "$HOME/.config/BraveSoftware/Brave-Origin" \
                     "$HOME/.config/BraveSoftware/Brave-Browser"; do
        lock="$profile/SingletonLock"
        [ -L "$lock" ] || continue

        target="$(${pkgs.coreutils}/bin/readlink "$lock")"   # "<host>-<pid>"
        lockhost="''${target%-*}"

        # Only act on the fatal cross-host case. Same-host stale locks are
        # handled by Brave itself and must be left alone.
        [ -n "$lockhost" ] && [ "$lockhost" != "$HOST" ] || continue

        ${pkgs.coreutils}/bin/rm -f \
          "$profile/SingletonLock" \
          "$profile/SingletonCookie" \
          "$profile/SingletonSocket"
      done
      exit 0
    '');
  };
  Install.WantedBy = [ "graphical-session.target" ];
};
```

### 3.3 Design decisions

| Decision | Rationale |
|---|---|
| **No stamp file** — runs every graphical-session start | Unlike the dock migration, a stale lock can reappear after any unclean shutdown. The check is idempotent and ~instant. |
| **Cross-host only** (`lockhost != HOST`) | Minimal surgical fix. Brave's own same-host stale-lock detection already works; touching it would be scope creep and risk. |
| **`pgrep -u $UID -x brave` guard** | Defensive: if the unit is restarted mid-session by a `nixos-rebuild switch` while Brave is open, do nothing. (Both `brave` and `brave-origin` exec a binary named `brave`.) |
| **Short `hostname`** (`pkgs.nettools`/`pkgs.hostname`) | Chromium uses `net::GetHostName()` which returns the short host name; must compare against the same form. |
| **Remove all three `Singleton*`** | Matches Chromium's own documented recovery step; `SingletonCookie`/`SingletonSocket` alone would leave Brave confused. |
| **`set -u`, no `set -e`** | A missing profile dir / broken readlink must not abort the loop; every branch already guards explicitly and ends `exit 0`. |
| **`Type=oneshot` + `RemainAfterExit`** | Same idiom as sibling services; runs once per session, shows as active. |
| Lives in `home/gnome-common-browser.nix` | Already the shared Brave addition for the 4 relevant roles; avoids a 5th duplicated block and avoids a new file. |
| **No `vexos.*` enable toggle** | Consistent with `gnome-common-browser.nix` (optionless). The only scenario needing an opt-out (Risk R1) is a deliberate, unusual manual Syncthing setup; documented with an override recipe instead of speculative config. |

### 3.4 One-shot manual remediation (delivered to user, not code)

For machines already broken (before this ships), or the second affected device:

```sh
rm -f ~/.config/BraveSoftware/Brave-Origin/Singleton{Lock,Cookie,Socket} \
      ~/.config/BraveSoftware/Brave-Browser/Singleton{Lock,Cookie,Socket}
```

(Already applied on `vextop` for `Brave-Origin` during diagnosis.)

---

## 4. Implementation steps

1. **`home/gnome-common-browser.nix`**
   - Add `{ pkgs, ... }` to the module argset (currently `{ ... }`).
   - Add the `systemd.user.services.vexos-brave-clear-stale-lock` block from
     §3.2, with a header comment block explaining the cross-host lock mechanism
     and linking this spec.
   - Verify: `nix flake show --impure` still lists all outputs; the four roles
     that import this file evaluate.

2. **No changes** to `home-*.nix`, `modules/`, `pkgs/`, or `flake.nix`.

3. **Verify package refs**: confirm the exact attr for the short hostname binary
   (`pkgs.hostname` vs `pkgs.nettools`) and `pkgs.procps` (`pgrep`) resolve on
   this nixpkgs pin during dry-build. Prefer `pkgs.hostname` if present (smaller
   closure); fall back to `pkgs.nettools`.

4. **Phase 3 build validation** (per CLAUDE.md):
   - `nix flake show --impure`
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
   - Touches a stateless-imported module → also:
     `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd`
   - Touches a server-imported module → also:
     `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
   - `git ls-files hardware-configuration.nix` → empty
   - `system.stateVersion` unchanged in all `configuration-*.nix`
   - No new flake inputs.

5. **Manual functional check** (post dry-build, optional, non-gating):
   ```sh
   mkdir -p ~/.config/BraveSoftware/Brave-Origin
   ln -sfn "fakehost-999999" ~/.config/BraveSoftware/Brave-Origin/SingletonLock
   systemctl --user start vexos-brave-clear-stale-lock
   test ! -e ~/.config/BraveSoftware/Brave-Origin/SingletonLock && echo OK
   # and the negative case:
   ln -sfn "$(hostname)-999999" ~/.config/BraveSoftware/Brave-Origin/SingletonLock
   systemctl --user start vexos-brave-clear-stale-lock
   test -e ~/.config/BraveSoftware/Brave-Origin/SingletonLock && echo "OK (same-host left alone)"
   ```

6. **Phase 6**: `bash scripts/preflight.sh` → exit 0.

---

## 5. Dependencies

No new flake inputs, no new external libraries. Uses `pkgs.coreutils`,
`pkgs.procps`, and `pkgs.hostname` (or `pkgs.nettools`) — all already in the
closure of these roles. Context7 not applicable (no versioned external API).

---

## 6. Configuration changes

None user-facing. New `systemd --user` unit `vexos-brave-clear-stale-lock` on
the `desktop`, `server`, `htpc`, and `stateless` roles, wanted by
`graphical-session.target`.

---

## 7. Risks and mitigations

| ID | Risk | Likelihood | Mitigation |
|----|------|------------|------------|
| **R1** | User manually configures Syncthing (server role) to sync `~/.config/BraveSoftware` across two machines running Brave *simultaneously*; the sweep removes the cross-host lock that Chromium uses to prevent concurrent-write profile corruption. | Very low — requires enabling the off-by-default module, manually adding the whole-home/config folder, and concurrent use. Even Brave's guard only turns this into a manual "unlock?" prompt, not real protection. | Document prominently in the module comment + Phase 7 notes: to opt out, override the unit: `systemd.user.services.vexos-brave-clear-stale-lock.Service.ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";`. Sweep is also gated on "no Brave running for this user", narrowing the window. |
| **R2** | `pkgs.hostname` attr name differs on this nixpkgs pin → eval failure. | Low | Implementation step 3 verifies during dry-build; `pkgs.nettools` is the fallback (already used widely in nixpkgs for `hostname`). |
| **R3** | Unit restarted mid-session by `nixos-rebuild switch` while Brave is open, racing a legitimately-created lock. | Low | `pgrep -u $UID -x brave` guard: if Brave is running, exit without touching anything. A cross-host lock while Brave runs locally is impossible anyway (local Brave writes the local hostname). |
| **R4** | `graphical-session.target` ordering: on some setups user services start before `$HOME` XDG dirs exist. | Very low | Script guards every path with `[ -L ... ] || continue`; absent dirs are a clean no-op. |
| **R5** | Future: Chromium changes the lock target format (e.g. adds FQDN). | Low | `''${target%-*}` strips only the trailing `-<pid>`; an FQDN host would still compare unequal to the short name and trigger a (harmless, correct) clear when no Brave runs. Acceptable. |
| **R6** | Scope creep into deduplicating `vexos-migrate-dock-brave-origin`. | n/a | Explicitly out of scope; note as tech debt in Phase 7 summary only. |

---

## 8. Research sources

1. **Direct reproduction** on `vextop` — `process_singleton_posix.cc:365` +
   `process_singleton_dialog_linux.cc:93` in Brave Origin 1.94.x stderr; disk
   state of `~/.config/BraveSoftware/Brave-Origin/Singleton*`.
2. Chromium bug tracker — *"Cannot start chrome after changing hostname"*,
   groups.google.com/a/chromium.org/g/chromium-bugs/c/YZayU3W1r7w (issue 367048).
3. Chromium issue 40944552 — *"Chrome does not start if profile is locked,
   silently exits"*, issues.chromium.org/issues/40944552.
4. FullPageOS issue #508 — *"Chromium not starting when hostname is changed"*,
   github.com/guysoft/FullPageOS/issues/508.
5. pikiosk issue #8 — *"Chrome profile lock after changing hostname"*,
   github.com/chriso0710/pikiosk/issues/8.
6. sleeplessbeastie's notes (2025-06-20) — *"How to unlock Google Chrome profile
   used by another process"* (`find ... -name 'Singleton*' -type l -delete`).
7. Ubuntu Launchpad Q#183930 — deleting `SingletonLock` for the chromium
   package.
8. brave/browser-laptop issue #11829 — *"Profile in use by another Chromium
   process — process_singleton_posix.cc"*.

Consensus across 2–8: the `SingletonLock` symlink encodes `<hostname>-<pid>`; a
hostname change makes Chromium treat the profile as remote; the fix is to delete
the stale `Singleton*` symlinks; a dialog is *supposed* to offer this but is
absent on minimal/headless-ish Linux sessions.
