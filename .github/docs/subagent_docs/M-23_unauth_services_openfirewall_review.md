# M-23 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-23_unauth_services_openfirewall_spec.md`

## Modified Files

- `modules/server/loki.nix`, `netdata.nix`, `zigbee2mqtt.nix`, `portbook.nix` — added
  `openFirewall` option (default `true`), wired
  `networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall <port>;`, added a
  warning comment about the lack of built-in authentication.
- `modules/server/kiji-proxy.nix` — same, but `openFirewall` defaults to `false`,
  matching its own documented localhost-only usage pattern.

## Review Findings

1. **Specification Compliance** — matches the spec: four services default to `true`
   (preserving current behavior, adding an opt-out), kiji-proxy defaults to `false`
   (a deliberate behavior change, justified and documented).
2. **Best Practices** — the kiji-proxy bind-address question (MASTER_PLAN's literal
   "bind to loopback") was resolved via the firewall rather than guessing at the
   binary's undocumented `PROXY_PORT` format — verified via the upstream README that
   this isn't documented, and a wrong guess risked silently breaking the proxy. The
   firewall-level fix achieves the identical practical outcome (nothing else on the
   LAN can reach it) without that risk.
3. **Consistency** — all five follow the exact `openFirewall` option pattern already
   established elsewhere in this codebase (e.g. `vaultwarden.nix`).
4. **Maintainability** — each module's header now documents its own auth gap
   explicitly, so a user deciding whether to flip `openFirewall` sees the tradeoff.
5. **Completeness** — all 5 cited services addressed.
6. **Performance** — no change.
7. **Security** — this is the core fix: kiji-proxy (the most sensitive of the five —
   proxies AI API traffic, potentially including API keys) is no longer LAN-exposed by
   default; the other four gained an opt-out without changing default behavior.
8. **API Currency** — n/a for the option additions; the kiji-proxy bind-format question
   was investigated against the upstream project's README rather than assumed.
9. **Build Validation:**
   - Forced-branch test (loki, netdata, kiji-proxy, portbook all enabled together,
     zigbee2mqtt excluded — see finding below): confirmed the merged
     `networking.firewall.allowedTCPPorts` contains 3100/19999/7777 (the three
     default-true services) and correctly excludes 8080 (kiji-proxy, default-false),
     and the full toplevel builds successfully.
   - Forced-branch override test: `loki.openFirewall = false` correctly removes 3100;
     `kiji-proxy.openFirewall = true` correctly adds 8080 — confirms the option works
     bidirectionally, not just in its default state.
   - `nix flake show --impure` — passed.
   - Required targets (`vexos-desktop-amd`, `-nvidia`, `-vm`) evaluated cleanly.
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `system.stateVersion` — untouched. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs as every
     prior review this session; nothing new.

## Finding Outside This Fix's Scope (flagged, not fixed)

Forcing `vexos.server.zigbee2mqtt.enable = true` to full-build (needed to verify this
fix for that module specifically) surfaced a genuine, **pre-existing** conflict
unrelated to this change:
`services.zigbee2mqtt.settings.homeassistant' is defined multiple times` — our
module's plain `homeassistant = false;` boolean assignment conflicts with the upstream
NixOS module's own default for that same key at the pinned nixpkgs revision (which
appears to now expect a submodule shape, not a plain boolean). Confirmed this is
completely independent of the `openFirewall` change (occurs identically with
`zigbee2mqtt.enable = true` alone, with none of this fix's other services enabled).
Not fixed here — flagged per Surgical Changes as a separate, real bug worth its own
MASTER_PLAN item. The `openFirewall` option and firewall-port wiring for
`zigbee2mqtt.nix` were still verified independently via `nix eval` on the
non-forcing-build-path (`networking.firewall.allowedTCPPorts` evaluates correctly on
its own without forcing the full `toplevel`, since Nix's laziness let that attribute
resolve without triggering the unrelated `settings.homeassistant` conflict).

No CRITICAL or RECOMMENDED issues found in the change itself.

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100%* | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100%* | A |

*zigbee2mqtt's `openFirewall` logic verified via targeted attribute evaluation, not a
full `toplevel` build, due to the unrelated pre-existing conflict noted above.

**Overall Grade: A (100%, with the zigbee2mqtt finding noted for a future fix)**

## Returns

- Build result: PASS
- **PASS**
