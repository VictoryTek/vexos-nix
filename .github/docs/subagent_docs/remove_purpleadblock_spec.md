# Remove PurpleAdBlock, add Alternate Player for Twitch.tv — Spec

## Addendum: replace with Alternate Player for Twitch.tv
User follow-up: instead of leaving PurpleAdBlock's slot empty, add "Alternate
Player for Twitch.tv". Verified via the AMO v5 API (same verification
standard the file's header comment requires):
- GUID: `twitch5@coolcmd`
- Slug: `twitch_5`
- Status: public, listed, active (current version 2026.6.21)

No Chrome Web Store listing exists for this extension (Firefox-only), so it
cannot go in the shared `extensions` list (which drives both Brave's
External Extensions mechanism and LibreWolf's policy). Instead it is added
as a second, LibreWolf-only entry in `ExtensionSettings`, keyed directly by
GUID with the same `installation_mode`/`install_url` shape as the shared
list produces, so it stays editable/removable rather than locked.


## Current State Analysis
`home/browser-extensions.nix` preinstalls 5 browser extensions into Brave Origin
and LibreWolf for every role that imports it (desktop, server, htpc, stateless).
One entry, `purpleads` (display name "PurpleAdBlock"), is defined at line 24:

```nix
{ name = "purpleads";  id = "lkgcfobnmghhbhgekffaadadhmeoindg"; amoGuid = "{a7399979-5203-4489-9861-b168187b52e1}";     amoSlug = "purpleadblock"; }
```

It is consumed generically by the `extensions` list via `map`/`listToAttrs` in
both the Brave Origin (`home.file` External Extensions JSON) and LibreWolf
(`programs.librewolf.policies.ExtensionSettings`) blocks. No other file
references `"purpleads"` by name.

## Problem Definition
The user wants the PurpleAdBlock extension no longer preinstalled on any role.

## Proposed Solution
Delete the single list entry. The remaining 4 extensions (bitwarden,
clearcache, smarthttps, tabliss) are unaffected since the consuming logic
iterates generically over the list.

## Implementation Steps
1. Remove the `purpleads` entry from the `extensions` list in
   `home/browser-extensions.nix`.

No new files, no `lib.mkIf` guards, no module architecture changes — this is a
data-only edit within an existing role-addition file (Option B pattern
unaffected).

## Dependencies
None. No new flake inputs, no Context7 lookup needed (no external library/API
integration — this is a static extension-ID list already verified against
Chrome Web Store / AMO).

## Configuration Changes
None beyond the list edit.

## Risks and Mitigations
- **Risk:** None significant — removing one entry from a generically-consumed
  list cannot affect the remaining entries or break `map`/`listToAttrs`.
- **Mitigation:** Verify via `nix eval --impure` that affected
  `nixosConfigurations` for desktop/server/htpc/stateless roles still
  evaluate successfully.
