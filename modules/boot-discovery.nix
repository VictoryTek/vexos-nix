# modules/boot-discovery.nix
# Automatically discovers OSes on other drives and registers UEFI NVRAM entries
# for them so that systemd-boot presents them as Type 3 "firmware" entries.
#
# Runs once per boot as a oneshot service. No per-host configuration required.
# The service is a no-op when no other EFI System Partitions are found.
{ pkgs, ... }:
let
  discoveryScript = pkgs.writeShellScript "vexos-boot-discovery" ''
    set -euo pipefail

    ESP_PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"

    # Resolve the primary ESP device (mounted at /boot)
    primary_esp="$(findmnt -n -o SOURCE /boot 2>/dev/null || true)"

    # Snapshot NVRAM entries once for deduplication checks
    nvram="$(efibootmgr 2>/dev/null || true)"

    # register <disk> <part_num> <loader> <label>
    #   Creates a UEFI NVRAM entry if one with the given label does not already exist.
    register() {
      local disk="$1" part_num="$2" loader="$3" label="$4"
      if echo "$nvram" | grep -qF "$label"; then
        return 0
      fi
      efibootmgr --create \
        --disk "$disk" \
        --part "$part_num" \
        --loader "$loader" \
        --label "$label" \
        >/dev/null 2>&1 || true
    }

    for esp_link in /dev/disk/by-parttype/''${ESP_PARTTYPE}*; do
      [[ -e "$esp_link" ]] || continue
      esp_dev="$(readlink -f "$esp_link")"

      # Skip the primary ESP
      [[ "$esp_dev" == "$primary_esp" ]] && continue

      disk="$(lsblk -no PKNAME "$esp_dev" 2>/dev/null || true)"
      part_num="$(lsblk -no PARTN "$esp_dev" 2>/dev/null || true)"
      partuuid="$(lsblk -no PARTUUID "$esp_dev" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
      [[ -z "$disk" || -z "$part_num" || -z "$partuuid" ]] && continue

      # 8-char PARTUUID prefix makes labels unique and idempotent per drive
      tag="''${partuuid:0:8}"

      mnt="$(mktemp -d)"
      if ! mount -r -t vfat "$esp_dev" "$mnt" 2>/dev/null; then
        rmdir "$mnt"
        continue
      fi

      # ── Windows ──────────────────────────────────────────────────────────
      if [[ -f "$mnt/EFI/Microsoft/Boot/bootmgfw.efi" ]]; then
        register "/dev/$disk" "$part_num" \
          '\EFI\Microsoft\Boot\bootmgfw.efi' \
          "Windows Boot Manager [$tag]"
      fi

      # ── Other Linux distros (first match per ESP) ─────────────────────────
      for entry in \
          "EFI/ubuntu/shimx64.efi:Ubuntu" \
          "EFI/fedora/shimx64.efi:Fedora" \
          "EFI/arch/grubx64.efi:Arch Linux" \
          "EFI/debian/shimx64.efi:Debian" \
          "EFI/pop/shimx64.efi:Pop!_OS" \
          "EFI/manjaro/grubx64.efi:Manjaro"; do
        efi_path="''${entry%%:*}"
        label_name="''${entry##*:}"
        if [[ -f "$mnt/$efi_path" ]]; then
          loader="\\''${efi_path//\//\\}"
          register "/dev/$disk" "$part_num" "$loader" "$label_name [$tag]"
          break
        fi
      done

      # ── Another NixOS / systemd-boot drive ───────────────────────────────
      # Registers the other drive's systemd-boot as an entry; selecting it
      # opens that drive's own boot menu with its NixOS generations.
      if [[ -f "$mnt/EFI/systemd/systemd-bootx64.efi" ]]; then
        register "/dev/$disk" "$part_num" \
          '\EFI\systemd\systemd-bootx64.efi' \
          "NixOS/systemd-boot [$tag]"
      fi

      umount "$mnt"
      rmdir "$mnt"
    done
  '';
in
{
  systemd.services.vexos-boot-discovery = {
    description = "Register UEFI boot entries for OSes on other drives";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = discoveryScript;
    };
    path = with pkgs; [ efibootmgr util-linux ];
  };
}
