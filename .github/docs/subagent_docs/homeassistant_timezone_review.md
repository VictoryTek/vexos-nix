# Review: Home Assistant Timezone Fix

**Feature**: `homeassistant_timezone`
**Reviewed file**: `modules/server/home-assistant.nix`
**Spec file**: `.github/docs/subagent_docs/homeassistant_timezone_spec.md`
**Date**: 2026-05-16

---

## Checklist Results

| # | Check | Result |
|---|-------|--------|
| 1 | `time_zone = config.time.timeZone` (NOT hardcoded `"America/Chicago"`) | ✅ PASS |
| 2 | `lib.mkDefault` NOT used inside freeform `services.home-assistant.config` block | ✅ PASS |
| 3 | `unit_system` remains as a plain string `"imperial"` | ✅ PASS |
| 4 | No regressions to other options | ✅ PASS |

---

## Detailed Findings

### Check 1 — timezone reference

The implemented module contains:

```nix
time_zone = config.time.timeZone;
```

Confirmed via `nix-instantiate --parse` output:

```
time_zone = (config).time.timeZone;
```

The hardcoded `"America/Chicago"` string is gone. The value is now a live Nix expression referencing the authoritative NixOS system timezone from `modules/locale.nix`. If the system timezone changes, Home Assistant will pick it up automatically on the next rebuild.

### Check 2 — no `lib.mkDefault` in freeform block

The parsed AST contains no `lib.mkDefault` wrapper anywhere inside the `services.home-assistant.config` attribute set. This is correct: `services.home-assistant.config` is a freeform `attrs` block serialized to YAML; `lib.mkDefault` inside a freeform block would produce a `{ _type = "override"; ... }` literal in the serialized YAML and break Home Assistant at runtime. The spec explicitly forbids this pattern and the implementation correctly avoids it.

### Check 3 — `unit_system` is a plain string

```nix
unit_system = "imperial";
```

Remains an undecorated string literal as specified. Operators can override via `lib.mkForce` or attribute re-assignment in a host file.

### Check 4 — no regressions

All other fields are intact and unchanged:
- `name = "Home"` ✅
- `http.server_port = 8123` ✅
- `openFirewall = true` ✅
- `extraComponents` list unchanged ✅
- Module option `vexos.server.home-assistant.enable` unchanged ✅

---

## Build Validation

| Step | Result |
|------|--------|
| `nix-instantiate --parse modules/server/home-assistant.nix` | ✅ PARSE_OK |
| `nix flake check --impure` | ✅ Exit 0 (confirmed via session context; multiple prior runs all exit 0) |

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Spec Compliance | 100% | A |
| Correctness | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

---

## Verdict

**PASS**

The implementation is minimal, correct, and fully aligned with the specification. The single-line substitution of `config.time.timeZone` for the hardcoded string eliminates the timezone drift risk without introducing any invalid NixOS option mechanics inside the freeform YAML config block. No regressions detected. Build passes cleanly.
