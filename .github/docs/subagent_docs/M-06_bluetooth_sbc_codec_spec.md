# M-06 — Bluetooth codec allowlist omits SBC

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-06 · `modules/audio.nix:38`

## Current State

```nix
"bluez5.codecs" = [ "aac" "ldac" "aptx" "aptx_hd" ];
```

`bluez5.codecs` in WirePlumber's bluez5 monitor config is an **allowlist** of codecs to
actually negotiate/enable — not a preference list with SBC implicitly available as a
fallback. SBC is the one mandatory baseline codec every A2DP-capable Bluetooth audio
device supports; the higher-quality codecs listed (AAC/LDAC/aptX/aptX HD) are optional
and vendor-specific. Since SBC isn't in the allowlist, any device that *only* speaks
SBC (no AAC/LDAC/aptX support — common on cheaper or older headphones/speakers) shares
zero codecs with this host's enabled set, so A2DP (stereo) negotiation fails outright
for those devices, even though `enable-sbc-xq`/`enable-msbc` are already turned on two
lines above (which control SBC *quality variants*, not whether SBC itself is usable at
all — those settings are inert without SBC in the codecs list).

## Problem Definition

Add SBC (and its higher-quality XQ variant, already enabled via `enable-sbc-xq`) to the
codec allowlist so SBC-only devices can pair and play audio at all.

## Proposed Solution

`"bluez5.codecs" = [ "sbc" "sbc_xq" "aac" "ldac" "aptx" "aptx_hd" ];` — SBC first, since
it's the universal baseline every device supports; the higher-quality codecs remain
listed after so WirePlumber still prefers them when both sides support one.

## Implementation Steps

1. `modules/audio.nix` — add `"sbc"` and `"sbc_xq"` to the `bluez5.codecs` list.

## Configuration Changes

None.

## Risks and Mitigations

- **None identified** — purely additive to an allowlist; existing devices that already
  negotiate AAC/LDAC/aptX are unaffected, since WirePlumber still prefers the
  highest-quality codec both sides support.
