# Preinstalled Browser Extensions + Vertical Tabs — Spec

## Current State Analysis

Two browsers are installed across the desktop/htpc/server/stateless roles:

- **Brave Origin** (`pkgs.vexos.brave-origin`, `pkgs/brave-origin/default.nix`) — a
  raw upstream binary wrapped as a plain Nix derivation, installed via
  `modules/packages-desktop.nix` (`environment.systemPackages`). Not routed
  through home-manager's `programs.chromium` module. Per-user config dir
  (confirmed from `home/gnome-common-browser.nix`'s stale-lock handling):
  `~/.config/BraveSoftware/Brave-Origin`.
- **LibreWolf** — currently installed via Flatpak (`io.gitlab.librewolf-community`,
  added in the immediately preceding Zen→LibreWolf swap), pinned in
  `modules/flatpak.nix` `defaultApps` and referenced as
  `io.gitlab.librewolf-community[.desktop]` in six dock/favourites lists.

User confirmed via clarifying questions:
- Extensions to preinstall, exactly as shown in the user's own extensions page:
  **Bitwarden Password Manager**, **Clear Cache**, **Purple Ads Blocker**,
  **Smart HTTPS**, **Tabliss — A Beautiful New Tab**.
- Scope: Brave Origin + LibreWolf only (not Tor Browser — installing extensions
  on Tor Browser weakens its anti-fingerprinting model).
- Install mode: pre-seeded and user-editable (not locked/force-installed —
  removable/disableable afterward like any normal extension).
- Also wants vertical tabs on by default in both browsers.

## Problem Definition

Preinstall the same 5 extensions (editable, not locked) into both Brave Origin
and LibreWolf, and default both browsers to vertical tabs, all declaratively
via this flake — without requiring any manual post-install click-through.

## Research Findings (blocking discovery)

Investigated whether LibreWolf-via-Flatpak can support any of this
declaratively. It cannot:

- Fetched the actual Flathub manifest
  (`github/flathub/io.gitlab.librewolf-community` →
  `io.gitlab.librewolf-community.json`) — its `finish-args`/`add-extensions`
  declare no policy extension point (unlike Mozilla's own official Firefox
  Flatpak, which declares `org.mozilla.firefox.systemconfig` specifically so
  a host directory can be mounted at `/app/etc/firefox` for `policies.json`).
  LibreWolf's Flatpak declares only an unrelated app-extension point
  (`io.gitlab.librewolf_community.extension`, for optional codec-style addons).
- LibreWolf tracks Firefox **stable** (confirmed via web search), not ESR.
  Legacy "sideload an .xpi by dropping it in a folder" support was removed
  from Firefox stable in v74 (2020) and only survives on ESR.
- Net result: no supported, non-fragile way to preinstall extensions or set
  policy-level preference defaults into the Flatpak build.

Per user's decision, **LibreWolf moves from Flatpak to the native nixpkgs
`librewolf` package** (confirmed present in this repo's pinned stable
`nixos-26.05` channel, built and verified: `librewolf-155.0-1`, desktop file
`librewolf.desktop`). This unlocks home-manager's dedicated `programs.librewolf`
module.

### How each mechanism was verified (not guessed)

**Brave Origin (stays a raw system package):**
- Built the actual package in this repo's pinned nixpkgs and ran `strings` on
  the real `brave` binary inside it. Confirmed directly from the binary:
  - Managed-policy search path: `/etc/brave/policies` (with `/etc/chromium/policies`
    fallback) — not needed here since we want *editable*, not locked, install.
  - The `External Extensions` mechanism string is present — this is Chromium's
    standard **per-user**, non-enterprise, auto-install-but-removable extension
    channel: a JSON file at
    `<user-data-dir>/External Extensions/<extension-id>.json` containing
    `{"external_update_url": "https://clients2.google.com/service/update2/crx"}`.
    This is exactly the mechanism home-manager's own `programs.chromium.extensions`
    option uses under the hood (confirmed by reading that module's source) — it's
    the standard, well-tested "declarative but removable" install path, and needs
    no system `/etc` write and no enterprise policy engine at all.
  - Confirmed the real preference key controlling vertical tabs:
    `brave.tabs.vertical_tabs_enabled` (found directly in the binary's string
    table, alongside ~15 sibling `brave.tabs.vertical_tabs_*` layout prefs).
    No dedicated admin *policy* name exists for it (only internal C++ class
    names turned up), so it's set the same way this repo already seeds other
    one-time app defaults (`home/dank-material-shell.nix`'s `seedHyprlandConf`
    pattern): a `home.activation` script that writes the profile's
    `Default/Preferences` JSON **only if the file doesn't already exist**,
    i.e. a first-run-only default — same "editable afterward" semantics as
    everything else in this spec, and consistent with existing repo style.

**LibreWolf (moves to nixpkgs `programs.librewolf`):**
- Downloaded and read the actual home-manager `mkFirefoxModule.nix` source
  (not a webpage summary — the raw file, grepped directly). Confirmed:
  - `programs.<browser>.policies` is passed straight into the underlying
    nixpkgs `wrapFirefox` derivation as `extraPolicies`, which bakes a
    `distribution/policies.json` **into the wrapped package's own Nix store
    output**. This is fully self-contained per-user — no system `/etc` write,
    no sudo, no NixOS-level module needed (this sidesteps the exact problem an
    unrelated NixOS Discourse thread hit when using the generic
    `programs.firefox` + package-override approach, which does need a manual
    `/etc/firefox/policies` → `/etc/librewolf/policies` mapping; the dedicated
    `programs.librewolf` module doesn't have that problem).
  - `cfg.profiles == { }` is an explicitly allowed, asserted-safe state —
    no profile needs to be declared for `policies` to apply.
  - `home.packages = lib.optional (cfg.finalPackage != null) cfg.finalPackage;`
    — enabling the module automatically installs the wrapped package; no
    separate `home.packages` entry needed.
  - Mozilla's own Firefox policy schema (verified via Bitwarden's official
    Linux deployment doc, which documents this exact JSON shape) supports
    `ExtensionSettings` with `installation_mode: "normal_installed"` (installs
    automatically, user can disable/remove — as opposed to `force_installed`,
    which locks it) and a `Preferences` policy where each entry has
    `{"Value": ..., "Status": "default"}` — `"default"` sets the *starting*
    value but leaves it fully user-changeable afterward (as opposed to
    `"locked"`). Both map exactly to the user's "pre-seeded, editable" choice.
  - Confirmed via web search: Firefox vertical tabs needs both
    `sidebar.revamp` and `sidebar.verticalTabs` set `true`, shipped stable
    since Firefox 136 (LibreWolf 155.0-1 here is far beyond that).

### Extension IDs (verified against live Chrome Web Store / AMO listings and the AMO v5 API, not assumed)

| Extension | Chrome Web Store ID | Firefox (AMO) GUID | AMO slug |
|---|---|---|---|
| Bitwarden Password Manager | `nngceckbapebfimnlniiiahkandclblb` | `{446900e4-71c2-419f-a6a7-df9c091e268b}` | `bitwarden-password-manager` |
| Clear Cache | `cppjkneekbjaeellbfkmgnhonkkjfpdn` | `clearcache@michel.de.almeida` | `clearcache` |
| Purple Ads Blocker | `lkgcfobnmghhbhgekffaadadhmeoindg` | `{a7399979-5203-4489-9861-b168187b52e1}` | `purpleadblock` |
| Smart HTTPS | `cmleijjdpceldbelpnpkddofmcmcaknm` | `{b3e677f4-1150-4387-8629-da738260a48e}` | `smart-https-revived` |
| Tabliss — A Beautiful New Tab | `hipekcciheckooncpjeljhnekcoolahp` | `extension@tabliss.io` | `tabliss` |

(Clear Cache: same developer, TenSoja, on both stores — confirmed cross-checked.
Purple Ads Blocker: routes Twitch video requests through a third-party proxy
per its own description — a known, accepted characteristic of this specific
extension, not a defect introduced here; flagged for the user's awareness,
not a reason to withhold it since they explicitly asked for it by name.)

## Proposed Solution / Implementation Steps (Option B pattern)

1. **`pkgs/brave-origin/default.nix`** — no change (package itself untouched).

2. **New file `home/browser-extensions.nix`** — universal addition imported by
   the same 4 roles that already import `home/gnome-common-browser.nix`
   (desktop, htpc, server, stateless — vanilla and headless-server have no
   browsers, same exclusion `gnome-common-browser.nix` already documents):
   - `home.file."${braveConfigDir}/External Extensions/<id>.json"` for the 5
     Chrome Web Store IDs above (content: `{"external_update_url": "https://clients2.google.com/service/update2/crx"}`).
   - `home.activation.seedBraveVerticalTabs` — one-time (`if [ ! -f ... ]`)
     seed of `${braveConfigDir}/Default/Preferences` with
     `{"brave":{"tabs":{"vertical_tabs_enabled":true}}}`, following the exact
     `seedHyprlandConf` precedent in `home/dank-material-shell.nix`.
   - `programs.librewolf.enable = true;` with:
     - `policies.ExtensionSettings` — 5 entries keyed by AMO GUID, each
       `{"installation_mode": "normal_installed", "install_url": "https://addons.mozilla.org/firefox/downloads/latest/<slug>/latest.xpi"}`.
     - `policies.Preferences."sidebar.revamp"` and `."sidebar.verticalTabs"`,
       each `{"Value": true, "Status": "default"}`.

3. **`modules/flatpak.nix`** — remove `"io.gitlab.librewolf-community"` from
   `defaultApps` (LibreWolf is no longer Flatpak-installed).

4. **`home-desktop.nix`, `home-htpc.nix`, `home-server.nix`, `home-stateless.nix`**
   — add `./home/browser-extensions.nix` to each `imports` list (same set as
   `./home/gnome-common-browser.nix`).

5. **Dock/favourites references** — replace
   `io.gitlab.librewolf-community[.desktop]` → `librewolf.desktop` in the same
   6 places touched by the prior Zen→LibreWolf change:
   `home/noctalia.nix`, `home/dank-material-shell.nix`,
   `modules/gnome-desktop.nix`, `modules/gnome-htpc.nix`,
   `modules/gnome-server.nix`, `modules/gnome-stateless.nix`.

No `lib.mkIf` role/display/gaming guards added anywhere — `home/browser-extensions.nix`
is a universal-base file for the role set that imports it, matching Option B.

## Dependencies

No new flake inputs. `librewolf` and `programs.librewolf` both come from the
existing `nixpkgs` (stable) and `home-manager` inputs already pinned in
`flake.nix`, both already `follows`-pinned correctly. No Context7 lookup
applicable (Context7 doesn't index Flathub/AMO/Chrome-Web-Store listings or
NixOS/home-manager option schemas — verified instead via the NixOS MCP option
search, direct binary inspection, and the actual home-manager module source,
each cited above).

## Configuration Changes

- `modules/flatpak.nix`: one entry removed from `defaultApps`.
- New `home/browser-extensions.nix`.
- 4 `home-*.nix` files gain one import line each.
- 6 dock/favourites files: one string swapped each (same lines touched last
  time).
- No `system.stateVersion` changes. No new flake inputs, so no `follows`
  concerns.

## Risks and Mitigations

- **Brave vertical-tabs seed reliability**: writing a minimal `Preferences`
  JSON before first launch is a common, well-understood technique (Chromium's
  PrefService fills in anything absent with hardcoded defaults), but it's not
  an "officially guaranteed forever" API the way the Firefox `Preferences`
  policy is. **Mitigation**: this only ever runs once, only when the file is
  absent (fresh profile) — worst case it's a no-op and vertical tabs simply
  isn't pre-toggled, with no build failure and no impact on any other setting;
  documented here so the user can verify visually after their next rebuild.
- **Firefox `ExtensionSettings`/`Preferences` policy schema not enforced at
  Nix-eval time**: a typo in a GUID or slug would build fine and silently fail
  to install at runtime. **Mitigation**: every ID/GUID/slug above was pulled
  from a live store listing or the AMO v5 API directly, not typed from memory.
- **Purple Ads Blocker's third-party proxy**: routes Twitch video traffic
  through an external proxy (by design, per its own listing) — a
  characteristic of the extension itself, not something this change adds or
  can mitigate; noted for transparency since the user is trusting it with
  their traffic.
- **LibreWolf leaving Flatpak**: update cadence changes from Flathub's rolling
  updates to this repo's `nix flake update` / nixpkgs-26.05 point-release
  cadence — already accepted by the user when choosing this path.
