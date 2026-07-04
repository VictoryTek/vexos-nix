# zigbee2mqtt `settings.homeassistant` conflict

Status: Phase 1 (Research & Specification)
Source: found during M-23 review — pre-existing, unrelated to that fix

## Current State

`modules/server/zigbee2mqtt.nix` sets `services.zigbee2mqtt.settings.homeassistant =
false;` (a plain boolean). Verified against the pinned nixpkgs revision
(`nixos/modules/services/home-automation/zigbee2mqtt.nix`): the upstream module itself
now sets `services.zigbee2mqtt.settings.homeassistant.enabled = lib.mkDefault
config.services.home-assistant.enable;` — i.e., `homeassistant` is expected to be an
attrset with an `.enabled` key, not a bare boolean. `settings` is backed by
`pkgs.formats.yaml{}`'s freeform type, whose merge logic can't reconcile a bare boolean
definition with an attrset definition for the same key regardless of priority, raising
"defined multiple times... expected to be unique" the moment `zigbee2mqtt.enable =
true` is evaluated at all — a hard failure, not a warning, for every user of this
service.

## Problem Definition

Update our module to the current upstream shape.

## Proposed Solution

`homeassistant = false;` → `homeassistant.enabled = false;` — the value/intent
(disable the Home Assistant MQTT discovery integration) is unchanged; only the shape
matches what the current nixpkgs module expects.

## Implementation Steps

1. `modules/server/zigbee2mqtt.nix` — one-line change.

## Configuration Changes

None.

## Risks and Mitigations

- **None** — matches upstream's own documented current shape exactly, verified
  against the pinned nixpkgs revision, not guessed.
