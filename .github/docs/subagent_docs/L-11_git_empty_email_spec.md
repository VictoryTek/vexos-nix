# L-11 — programs.git ships user.email = ""

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-11 (BUGS L12) · `home/bash-common.nix:13-16`
(current file: matches the cited range exactly)

## Current State

`home/bash-common.nix:10-21`:
```nix
programs.git = {
  enable   = true;
  settings = {
    user = {
      name  = lib.mkDefault osConfig.vexos.user.name;
      email = lib.mkDefault "";
    };
    init.defaultBranch   = "main";
    pull.rebase          = true;
    push.autoSetupRemote = true;
  };
};
```

`email = lib.mkDefault ""` sets `user.email` to a present-but-empty
string, which home-manager's ini-style `programs.git.settings` renders
literally into `~/.config/git/config` as `email = ` — a real,
present key with an empty value, not an absent one.

**Re-verified the plan's stated failure mode directly rather than
trusting it** (this session's established practice — see H-02, M-13,
L-05, L-10 for prior cases where the original analysis needed
correction): tested `git commit` with `user.name` set to a real value
and `user.email` set to `""` (the exact combination this file
produces). Result: **the commit succeeds** (exit 0) — git records the
author as `Name <>` (empty angle brackets), it does not refuse. Traced
why: git's hard failure ("empty ident name ... not allowed") triggers
specifically on an **empty user.name**, not an empty user.email — a
distinct field. So the MASTER_PLAN/BUGS-L12 title's literal claim
("git refuses to commit with an explicit empty value") does not
reproduce for this repo's actual configuration (name is always set via
`osConfig.vexos.user.name`; only email is blank).

This narrows, but does not eliminate, the real problem: shipping a
present-but-empty `user.email` means every commit made under this
system identity — in *any* repository the user works in interactively,
not just `/etc/nixos` — silently records a malformed, blank email
(`Name <>`) instead of a real address. This is worse than leaving the
key **absent** entirely: with the key absent, git falls back to its own
environment-based auto-detection (`$EMAIL`, or a
`user@hostname.(none)` guess) and prints a one-time warning asking the
user to configure a real identity — which is exactly the nudge the
file's own comment ("fill it in here or override in the role's
home-*.nix") intends, but an empty-string default silently defeats that
nudge by making the key already "present" as far as git's identity
check is concerned.

## Problem Definition

`programs.git.settings.user.email` is set to a literal empty string
rather than being left unset, which:
1. Does not actually block `git commit` (correcting the plan's literal
   premise), but
2. Produces malformed blank-email commit authorship
   (`Name <>`) on every commit made under this identity, and
3. Suppresses git's own built-in "please configure your identity"
   warning/fallback, which only fires when the key is genuinely absent.

## Proposed Solution

Remove the `email` key entirely from `programs.git.settings.user`,
matching the plan's suggested fix. This leaves `user.name` (still
sensibly defaulted from `osConfig.vexos.user.name`) in place, and lets
git's own identity-detection fallback handle email the way it's
designed to — including its own warning — until a user or role
overrides it.

## Implementation Steps

1. `home/bash-common.nix` — delete the `email = lib.mkDefault "";`
   line from the `user` attrset (leaving `name` untouched).
2. Update the header comment (lines 7-9) to no longer say email is
   "intentionally left blank" via a default value — instead note it's
   left unset so git's own fallback/warning applies, and it can still
   be overridden the same way (role's `home-*.nix`, or the user's own
   `~/.config/git/config`, or `programs.git.settings.user.email` in a
   role override — `lib.mkDefault` here means any override anywhere
   still wins the same way it did before).

## Configuration Changes

None — no new NixOS/home-manager options; only removes a value from an
existing option's attrset.

## Risks and Mitigations

- **Risk:** any role or override currently relying on the *presence* of
  an empty `user.email` (e.g. some tooling that checks
  `git config user.email` returns a defined-but-empty value rather than
  erroring on an unset key) could behave differently.
  **Mitigation:** grepped the repo for any `git config user.email` or
  equivalent consumer — none found; nothing else in this repo reads or
  depends on this value.
- **Risk:** users who never set a real email will now see git's
  one-time interactive warning on first commit in any repo (e.g. the
  first `/etc/nixos` commit made by the installer's own git-tracking
  step).
  **Mitigation:** verify in Phase 3 whether any of this repo's own
  scripts (`install.sh`, `stateless-setup.sh`,
  `migrate-to-stateless.sh`, `vexos-update`) run `git commit` under
  this *user's* home-manager git config specifically, or whether they
  all use `git -c user.email=... commit` / run as `root` (a different,
  unrelated git identity not affected by this file at all). If any of
  them do rely on this user-level config being silently non-interactive,
  that would need its own explicit `-c user.email=` override rather
  than depending on this file's default.
