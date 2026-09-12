# Zen Browser Flatpak Cleanup — Spec

## Current State Analysis

`app.zen_browser.zen` was fully removed from every config list in this repo by
the prior Zen→LibreWolf migration (`zen_to_librewolf_spec.md` /
`zen_to_librewolf_review.md`, both PASS, already committed). A repo-wide grep
for `zen` confirms zero remaining references outside unrelated false positives
(Ryzen microarchitecture comments, the Linux-Zen kernel scheduler note).

That migration's spec explicitly flagged, and deliberately left out of scope,
the following gap in `modules/flatpak.nix`:

> Zen was a plain `defaultApps` entry, not managed/excluded, so removing it
> from the list does not trigger automatic uninstall on existing hosts.

Confirmed live on this host via `flatpak list --app`: `app.zen_browser.zen`
is still installed. LibreWolf itself is installed correctly, but natively via
Home Manager's `programs.librewolf` (`home/browser-extensions.nix`) — it was
never a Flatpak, so it isn't part of `modules/flatpak.nix` at all.

This matches the user's report exactly: "installed librewolf, removed zen"
only did the first half — the new app was added, the old one was never
uninstalled from already-provisioned hosts.

## Problem Definition

Existing hosts that had Zen installed before the migration are left with a
dangling `app.zen_browser.zen` Flatpak that the reconciliation service never
removes, because it isn't tracked in `excludeApps` or `managedApps`, and
Zen's `defaultApps` entry was deleted outright rather than moved to either
list.

## Proposed Solution

`modules/flatpak.nix` already has a mechanism for exactly this case: the
"Remove globally banned apps" loop (lines 110–120) unconditionally uninstalls
a hardcoded app ID on every host, regardless of `excludeApps`/`managedApps`
config, currently used for `com.github.wwmm.easyeffects`. Add
`app.zen_browser.zen` to that same loop.

This is idempotent and safe on hosts that never had Zen (the `flatpak list |
grep -qx` guard skips silently) and on hosts that already cleaned it up
manually. No new option, no new file, no structural change — a one-line
addition to an existing unconditional-removal list that already exists for
this exact purpose.

Rejected alternative: adding it to `vexos.flatpak.excludeApps` per-role. That
option is meant for *ongoing* per-role policy ("this role should never have
X"), and would need to be set in every role's `configuration-*.nix` file for
this cleanup to reach all hosts — more surface area than the banned-apps loop,
which already runs unconditionally for every role that imports
`modules/flatpak.nix`.

## Implementation Steps (Option B pattern — no structural changes)

1. `modules/flatpak.nix` — add `app.zen_browser.zen` to the banned-apps `for`
   loop, with a one-line comment noting it's leftover-cleanup from the
   Zen→LibreWolf migration (so a future reader doesn't mistake it for a
   permanent policy ban and knows it can eventually be removed once no hosts
   have Zen left).

## Dependencies

None. No new flake inputs, no new Flatpak IDs — reusing the same
`app.zen_browser.zen` ID already verified in the prior migration.

## Configuration Changes

None beyond the one-line list addition. No new options, no
`system.stateVersion` change.

## Risks and Mitigations

- **Risk:** None significant — `flatpak uninstall` on an app that isn't
  installed is already guarded by the existing `flatpak list | grep -qx`
  check before every uninstall call in that loop.
- **Risk:** Dock/launcher pins were already swapped to `librewolf` in
  `home/noctalia.nix` and `home/dank-material-shell.nix` in the prior
  migration — no further change needed there. If a host's Home Manager
  generation still shows Zen pinned after this fix, that indicates the host's
  last activation didn't include the prior migration's commit (a
  `home-manager switch` / `nixos-rebuild switch` currency issue, not a config
  defect) — out of scope for this fix, called out separately to the user.
