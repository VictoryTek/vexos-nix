---
name: localsend-appfolder
description: Add LocalSend.desktop to the Utilities app folder on desktop and server GNOME roles
metadata:
  type: project
---

# Spec: LocalSend in Utilities App Folder

## Current State

`modules/gnome-desktop.nix` and `modules/gnome-server.nix` each define a
`org/gnome/desktop/app-folders/folders/Utilities` dconf key with a list of
`.desktop` IDs. `LocalSend.desktop` is not present in either.

## Problem

`localsend` was added to `packages-desktop.nix` in the previous task. Its
`.desktop` file (`LocalSend.desktop` — confirmed from the store path
`localsend-1.17.0/share/applications/LocalSend.desktop`) does not appear in
any GNOME app folder, so it sits loose in the app grid.

## Proposed Solution

Append `"LocalSend.desktop"` to the `apps` list of the `Utilities` folder in:
- `modules/gnome-desktop.nix` (desktop role)
- `modules/gnome-server.nix` (server role)

No new files, no new modules — these are the canonical per-role dconf overlays.

## Implementation Steps

1. `modules/gnome-desktop.nix` — add `"LocalSend.desktop"` to the Utilities folder apps list
2. `modules/gnome-server.nix` — add `"LocalSend.desktop"` to the Utilities folder apps list

## Risks

None. dconf app-folder membership is additive; an unrecognised `.desktop` ID is
silently ignored by GNOME Shell.
