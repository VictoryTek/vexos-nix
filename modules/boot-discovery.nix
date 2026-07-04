# modules/boot-discovery.nix
# Automatically discovers OSes on other drives and registers UEFI NVRAM entries
# for them so that systemd-boot presents them as Type 3 "firmware" entries.
#
# Runs once per boot as a oneshot service. No per-host configuration required.
# The service is a no-op when no other EFI System Partitions are found.
#
# ESP discovery uses sfdisk --dump to read partition tables (GPT or MBR)
# directly from raw block devices.  This works regardless of whether udev has
# created by-parttype symlinks or the kernel has populated PARTTYPE in sysfs —
# both of which were found to be absent on NVMe drives on this system.
{ pkgs, ... }:
let
  discoveryScript = pkgs.writeShellScript "vexos-boot-discovery" ''
    set -euo pipefail

    ESP_PARTTYPE="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
    log() { echo "[boot-discovery] $*"; }

    primary_esp="$(findmnt -n -o SOURCE /boot 2>/dev/null || true)"
    nvram="$(efibootmgr 2>/dev/null || true)"
    log "primary ESP: $primary_esp"

    register() {
      local disk="$1" part_num="$2" loader="$3" label="$4"
      if echo "$nvram" | grep -qF "$label"; then
        log "already registered: $label"
        return 0
      fi
      log "registering: $label (disk=$disk part=$part_num)"
      local out
      if out="$(efibootmgr --create \
        --disk "$disk" \
        --part "$part_num" \
        --loader "$loader" \
        --label "$label" 2>&1)"; then
        log "registered: $label"
      else
        log "FAILED to register $label: $out"
      fi
    }

    # Iterate every disk device and read its GPT via sfdisk --dump.
    # sfdisk reads the raw block device directly — no udev/sysfs dependency.
    while IFS=' ' read -r blk_name blk_type; do
      [[ "$blk_type" == "disk" ]] || continue

      while IFS= read -r sline; do
        # Match partition entries whose type is the ESP type — either the GPT
        # GUID (c12a7328-...) or, for MBR/DOS-labeled disks, the 2-hex-digit
        # code "ef". sfdisk --dump reports type= differently per table format:
        #   GPT: /dev/nvme0n1p1 : start=N, size=N, type=GUID, uuid=GUID
        #   MBR: /dev/sda1      : start=N, size=N, type=ef
        part_type="$(echo "''${sline,,}" | sed -n 's/.*type=\([^,]*\).*/\1/p')"
        [[ "$part_type" == "$ESP_PARTTYPE" || "$part_type" == "ef" ]] || continue

        # Extract partition device path (everything before " :")
        esp_dev="''${sline%% :*}"

        # Extract partition's own GUID (PARTUUID) for idempotency labels
        partuuid="$(echo "$sline" \
          | sed -n 's/.*uuid=\([A-Fa-f0-9-]*\).*/\1/p' \
          | tr '[:upper:]' '[:lower:]' || true)"

        [[ -b "$esp_dev" ]] || { log "skipping $esp_dev: not a block device"; continue; }
        [[ "$esp_dev" == "$primary_esp" ]] && { log "skipping primary ESP: $esp_dev"; continue; }

        # Partition number — try lsblk first, fall back to parsing device name
        part_num="$(lsblk -no PARTN "$esp_dev" 2>/dev/null || true)"
        [[ -z "$part_num" ]] && part_num="''${esp_dev##*[^0-9]}"

        log "found ESP: $esp_dev  disk=$blk_name part=$part_num partuuid=$partuuid"
        [[ -z "$blk_name" || -z "$part_num" ]] && { log "skipping $esp_dev: missing metadata"; continue; }

        tag="''${partuuid:0:8}"
        [[ -z "$tag" ]] && tag="''${esp_dev##*/}"

        mnt="$(mktemp -d)"
        if ! mount -r -t vfat "$esp_dev" "$mnt" 2>/dev/null; then
          log "could not mount $esp_dev as vfat — skipping"
          rmdir "$mnt"
          continue
        fi
        log "mounted $esp_dev — EFI subdirs: $(ls "$mnt/EFI/" 2>/dev/null | tr '\n' ' ' || echo 'empty/unreadable')"

        # ── Windows ──────────────────────────────────────────────────────────
        if [[ -f "$mnt/EFI/Microsoft/Boot/bootmgfw.efi" ]]; then
          register "/dev/$blk_name" "$part_num" \
            '\EFI\Microsoft\Boot\bootmgfw.efi' \
            "Windows Boot Manager [$tag]"
        fi

        # ── Other Linux distros (first match per ESP) ─────────────────────
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
            register "/dev/$blk_name" "$part_num" "$loader" "$label_name [$tag]"
            break
          fi
        done

        # ── Another NixOS / systemd-boot drive ───────────────────────────
        if [[ -f "$mnt/EFI/systemd/systemd-bootx64.efi" ]]; then
          register "/dev/$blk_name" "$part_num" \
            '\EFI\systemd\systemd-bootx64.efi' \
            "NixOS/systemd-boot [$tag]"
        fi

        umount "$mnt"
        rmdir "$mnt"
      done < <(sfdisk --dump "/dev/$blk_name" 2>/dev/null)
    done < <(lsblk -rno NAME,TYPE 2>/dev/null)

    log "done"
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
      StandardOutput = "journal";
      StandardError = "journal";
    };
    path = with pkgs; [ efibootmgr util-linux ];
  };
}
