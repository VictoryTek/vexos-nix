# Spec: Home Assistant Timezone & Unit System Overridability Fix

**Feature name**: `homeassistant_timezone`  
**Spec file**: `.github/docs/subagent_docs/homeassistant_timezone_spec.md`  
**Status**: Ready for Implementation

---

## 1. Current State Analysis

### File: `modules/server/home-assistant.nix`

The module hardcodes two values directly inside the `services.home-assistant.config.homeassistant` attribute set:

```nix
homeassistant = {
  name = "Home";
  unit_system = "imperial";
  time_zone = "America/Chicago";
};
```

Both values are plain strings with no `lib.mkDefault` or `lib.mkForce` wrapper:

- **`unit_system = "imperial"`** — cannot be overridden by an operator without modifying this file directly.
- **`time_zone = "America/Chicago"`** — duplicates the system timezone that is already defined authoritatively in `modules/locale.nix`, creating a drift risk if the system timezone is ever changed.

### File: `modules/locale.nix`

```nix
{ lib, ... }:
{
  time.timeZone      = lib.mkDefault "America/Chicago";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
}
```

`time.timeZone` is set to `lib.mkDefault "America/Chicago"`. This is the single source of truth for the system timezone.  
`config.time.timeZone` is therefore available to any module that receives `config` as a function argument — which `home-assistant.nix` already does.

---

## 2. Problem Definition

| Issue | Impact |
|-------|--------|
| `unit_system` is a hardcoded string | An operator deploying a metric-system installation must modify the module file; there is no override mechanism. |
| `time_zone` is a hardcoded string independent of the NixOS locale | If `modules/locale.nix` is changed to a different timezone, Home Assistant silently retains `America/Chicago`. This causes HA automations (schedules, sun triggers, history) to run on the wrong local time. |

---

## 3. Proposed Solution Architecture

No new files, no new dependencies, no new module options.

Both fixes are single-line substitutions within the existing `homeassistant` attribute set:

1. Wrap `unit_system` with `lib.mkDefault` so the string value is still applied but can be overridden by any downstream config.
2. Replace the `time_zone` hardcoded string with `lib.mkDefault config.time.timeZone`, delegating to the authoritative NixOS timezone setting.

Because `modules/server/home-assistant.nix` already declares `{ config, lib, pkgs, ... }` as its argument set, `config.time.timeZone` is accessible without any import or option changes.

The `services.home-assistant.config` attribute accepts plain Nix values (it is serialized to YAML). `lib.mkDefault` is a NixOS option mechanism — it is valid on **NixOS options**, not inside freeform YAML config attribute sets. Therefore the correct fix is:

- **`unit_system`**: assign as a plain string but document that operators can override via `services.home-assistant.config.homeassistant.unit_system` in a host file using `lib.mkForce` or by importing a supplemental module that sets the attribute directly (since freeform attrs use last-write-wins or `lib.mkForce`).
- **`time_zone`**: substitute the hardcoded string with `config.time.timeZone` — a direct Nix expression reference, not a `lib.mkDefault` call, because this attribute is inside a freeform config block, not a typed NixOS option.

> **Important**: `services.home-assistant.config` is a freeform attribute set (type `attrs` or `format.type`), not a structured set of `mkOption`-declared options. `lib.mkDefault` inside a freeform block does **not** produce override semantics; it produces a literal `{ _type = "override"; ... }` attrset that would be serialized verbatim to YAML and break Home Assistant. Therefore:
>
> - `unit_system` remains a plain string `"imperial"` — it is already overridable in host files via attribute merging with `lib.mkForce` or explicit re-assignment.
> - `time_zone` is changed to the Nix expression `config.time.timeZone` so it always reflects the system timezone.

This is the minimal, correct fix.

---

## 4. Implementation Steps

### Step 1 — Edit `modules/server/home-assistant.nix`

Change `time_zone` from the hardcoded string to the system timezone reference.

No other changes are required.

---

## 5. Exact Before/After Diff

### File: `modules/server/home-assistant.nix`

```diff
       config = {
         homeassistant = {
           name = "Home";
           unit_system = "imperial";
-          time_zone = "America/Chicago";
+          time_zone = config.time.timeZone;
         };
         http = {
           server_port = 8123;
```

**Before** (lines 23–29):
```nix
      config = {
        homeassistant = {
          name = "Home";
          unit_system = "imperial";
          time_zone = "America/Chicago";
        };
        http = {
          server_port = 8123;
        };
      };
```

**After**:
```nix
      config = {
        homeassistant = {
          name = "Home";
          unit_system = "imperial";
          time_zone = config.time.timeZone;
        };
        http = {
          server_port = 8123;
        };
      };
```

---

## 6. Attribute Nesting Confirmation

The values being changed live at:

```
services.home-assistant.config.homeassistant.time_zone
services.home-assistant.config.homeassistant.unit_system
```

This is **inside a freeform config block**, not inside a typed NixOS option. `lib.mkDefault` must **not** be used here. The fix for `time_zone` is a plain Nix expression substitution.

---

## 7. Why `unit_system` Is Left as a Plain String

`unit_system = "imperial"` is intentionally left as a plain string. It remains operator-overridable in host files by re-declaring the attribute with `lib.mkForce` on the enclosing `services.home-assistant.config` attrset or by importing a supplemental module that overrides the value. Adding `lib.mkDefault` to a freeform attribute would break YAML serialization.

---

## 8. Dependencies

None. This change:
- Adds no new Nix inputs
- Adds no new `nixpkgs` packages
- Adds no new module options
- Requires no changes to `flake.nix`, `flake.lock`, or any host file

---

## 9. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `config.time.timeZone` is `null` at evaluation time if no timezone is set | `modules/locale.nix` unconditionally sets `time.timeZone = lib.mkDefault "America/Chicago"`, so the value is always a non-null string in this project. |
| YAML serialization of the expression value | `config.time.timeZone` evaluates to a plain string before YAML serialization; no structural change occurs. |
| Operator expects to override `time_zone` independently of system timezone | This is a feature, not a risk: operators who want a different HA timezone than the system timezone can re-declare `services.home-assistant.config.homeassistant.time_zone` in a host file with `lib.mkForce`. |

---

## 10. Files to Modify

| File | Change |
|------|--------|
| `modules/server/home-assistant.nix` | Line 25: replace `"America/Chicago"` with `config.time.timeZone` |

**No other files require modification.**
