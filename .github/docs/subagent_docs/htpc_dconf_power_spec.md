# Specification: Remove Duplicate dconf Power Keys from `gnome-htpc.nix`

**Feature name:** `htpc_dconf_power`  
**Type:** Surgical deletion (no new files, no new logic)  
**Status:** Ready for implementation

---

## 1. Problem Statement

`modules/gnome-htpc.nix` (lines 64–67) contains a dconf settings block for
`org/gnome/settings-daemon/plugins/power` that sets exactly two keys:

```nix
"org/gnome/settings-daemon/plugins/power" = {
  sleep-inactive-ac-type      = "nothing";
  sleep-inactive-battery-type = "nothing";
};
```

`modules/system-nosleep.nix` (lines 51–59) already sets the **same two keys**
with the same values, plus three additional keys, inside a `lib.mkBefore`
database:

```nix
programs.dconf.profiles.user.databases = lib.mkBefore [
  {
    settings = {
      "org/gnome/settings-daemon/plugins/power" = {
        sleep-inactive-ac-type         = "nothing";
        sleep-inactive-battery-type    = "nothing";
        sleep-inactive-ac-timeout      = lib.gvariant.mkInt32 0;
        sleep-inactive-battery-timeout = lib.gvariant.mkInt32 0;
        power-button-action            = "nothing";
      };
    };
  }
];
```

`system-nosleep.nix` is the canonical, authoritative source for all
`org/gnome/settings-daemon/plugins/power` keys in this project. The block in
`gnome-htpc.nix` is a redundant duplicate that creates fragility: any future
editor who touches `gnome-htpc.nix` for unrelated reasons and changes
`sleep-inactive-ac-type` (e.g. to `"suspend"`) would silently override the
`system-nosleep` setting in the user-db chain without realising it, because the
htpc database appears later in the merged list and therefore wins on shared keys.

---

## 2. dconf Merge Semantics Confirmation

NixOS's `programs.dconf.profiles.user.databases` is a Nix list. Databases are
applied in list order; the **last entry wins** on duplicate keys (standard
dconf layering: each successive database in the profile takes precedence over
the previous one).

`lib.mkBefore` inserts the `system-nosleep` database at the **front** of the
list (lowest precedence). The htpc role's database (added by `gnome-htpc.nix`
without ordering priority) is appended after it, making it the later (higher
precedence) entry.

Consequence today: the htpc database overrides the `system-nosleep` values for
the two shared keys. Since both set `"nothing"` the observable behaviour is
identical. However the override relationship is backwards — the protective
module (`system-nosleep`) is being silently overridden by the role-specific
display module (`gnome-htpc`), which is semantically wrong.

After the fix, `system-nosleep` is the sole setter of all five keys and the
override risk is eliminated.

---

## 3. Canonical Source Verification

`system-nosleep.nix` sets the following keys that `gnome-htpc.nix` does **not**:

| Key | Value |
|-----|-------|
| `sleep-inactive-ac-timeout` | `lib.gvariant.mkInt32 0` |
| `sleep-inactive-battery-timeout` | `lib.gvariant.mkInt32 0` |
| `power-button-action` | `"nothing"` |

This confirms that `system-nosleep.nix` is the comprehensive, canonical setter
for this entire dconf path. `gnome-htpc.nix` only covers a partial subset.

---

## 4. Import Analysis / Risk Assessment

Grep results for modules importing each file:

| Configuration file | Imports `gnome-htpc.nix` | Imports `system-nosleep.nix` |
|--------------------|:------------------------:|:-----------------------------:|
| `configuration-htpc.nix` | ✅ (line 6) | ✅ (line 18) |
| `configuration-desktop.nix` | ❌ | ✅ (line 23) |
| `configuration-stateless.nix` | ❌ | ✅ (line 17) |
| `configuration-server.nix` | ❌ | ✅ (line 17) |
| `configuration-headless-server.nix` | ❌ | ✅ (line 10) |
| `configuration-vanilla.nix` | ❌ | ❌ |

**Finding:** `gnome-htpc.nix` is imported by exactly **one** configuration file:
`configuration-htpc.nix`. That same file also imports `system-nosleep.nix`.

**Risk: NONE.** There is no role that imports `gnome-htpc.nix` without also
importing `system-nosleep.nix`. Removing the duplicate block from
`gnome-htpc.nix` does not lose the `"nothing"` setting for any role. The HTPC
role continues to receive all five power keys from `system-nosleep.nix`.

---

## 5. No Other Setters

A workspace-wide grep for `sleep-inactive-ac-type`, `sleep-inactive-battery-type`,
and `settings-daemon/plugins/power` confirms these keys appear in exactly two files:

- `modules/gnome-htpc.nix` — the duplicate (to be removed)
- `modules/system-nosleep.nix` — the canonical source (retained as-is)

No other module in the project sets any key under
`org/gnome/settings-daemon/plugins/power`.

---

## 6. Implementation: Exact Change

### File to modify
`modules/gnome-htpc.nix`

### Lines to remove (lines 62–68 in context)

Remove the entire `"org/gnome/settings-daemon/plugins/power"` attribute set,
including the blank line that precedes it within the `settings` block.

**Exact surrounding context for precise identification (use as oldString):**

```nix
        "org/gnome/shell/extensions/dash-to-dock" = {
          dock-position = "LEFT";
          autohide      = true;
          intellihide   = true;
        };

        "org/gnome/settings-daemon/plugins/power" = {
          sleep-inactive-ac-type      = "nothing";
          sleep-inactive-battery-type = "nothing";
        };

        "org/gnome/desktop/app-folders" = {
```

**Replace with (newString — the power block and its preceding blank line are removed):**

```nix
        "org/gnome/shell/extensions/dash-to-dock" = {
          dock-position = "LEFT";
          autohide      = true;
          intellihide   = true;
        };

        "org/gnome/desktop/app-folders" = {
```

### No other files require modification.

---

## 7. Architecture Rule Compliance

- **No `lib.mkIf` guards added** ✅
- **No new files created** ✅
- **Pure deletion** ✅
- **Option B (common base + role additions) pattern preserved** ✅

---

## 8. Verification Steps

After applying the change:

1. **Grep check:** Run `grep -r "sleep-inactive-ac-type" modules/` — must return
   only one hit: `modules/system-nosleep.nix`.

2. **Grep check:** Run `grep -r "settings-daemon/plugins/power" modules/` — must
   return only one hit: `modules/system-nosleep.nix`.

3. **Flake check:** `nix flake check` must pass with no evaluation errors.

4. **Dry-build HTPC:** `sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd`
   (and at least one other GPU variant, e.g. `vexos-htpc-nvidia`) must succeed,
   confirming the HTPC system closure still builds correctly.

5. **Optional runtime check:** On a live HTPC system after `nixos-rebuild switch`,
   run:
   ```
   gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type
   ```
   Expected output: `'nothing'`

---

## 9. Summary

| Item | Value |
|------|-------|
| File modified | `modules/gnome-htpc.nix` |
| Lines removed | 4 lines (blank + 3-line attribute set) |
| Functional impact | None — `system-nosleep.nix` already covers these keys |
| Risk | None — no role imports `gnome-htpc.nix` without `system-nosleep.nix` |
| New files | None |
| New logic | None |
