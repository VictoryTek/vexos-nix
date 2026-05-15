# home/photogimp.nix
#
# PhotoGIMP: Transforms GIMP's interface to resemble Adobe Photoshop.
# Source: https://github.com/Diolinux/PhotoGIMP
#
# Strategy:
#   1. Fetch PhotoGIMP at build time (pkgs.fetchFromGitHub).
#   2. Install icons into the user hicolor theme via xdg.dataFile (symlinks).
#   3. Override the GIMP .desktop with PhotoGIMP branding via xdg.dataFile (text),
#      placing the file at ~/.local/share/applications/ as a file-level symlink
#      so GNOME's inotify watcher detects changes on generation switch.
#   4. Copy GIMP plugin/config files into ~/.config/GIMP/3.0/ at activation
#      (copy, not symlink — GIMP writes to its own config dir at runtime).
#      A version sentinel prevents re-copying on every switch.
#   5. Run gtk-update-icon-cache and update-desktop-database at activation
#      so GNOME picks up the new icon and renamed launcher immediately.
#
# Works with: GIMP 3.0 installed via Flatpak (org.gimp.GIMP)
# Config target: ~/.config/GIMP/3.0/

{ config, lib, pkgs, ... }:

let
  photogimpVersion = "3.0";

  photogimp = pkgs.fetchFromGitHub {
    owner = "Diolinux";
    repo  = "PhotoGIMP";
    rev   = photogimpVersion;
    # Refresh with:
    #   nix-prefetch-url --unpack \
    #     "https://github.com/Diolinux/PhotoGIMP/archive/refs/tags/3.0.tar.gz"
    hash = "sha256-R9MMidsR2+QFX6tu+j5k2BejxZ+RGwzA0DR9GheO89M=";
  };
in
{
  options.photogimp.enable = lib.mkEnableOption "PhotoGIMP GIMP configuration overlay";

  config = lib.mkIf config.photogimp.enable {

    # ── Step 1: cleanup orphaned non-symlink files ──────────────────────────
    # Home Manager manages icons and the .desktop as symlinks.
    # If a previous manual install left real files in those paths, activation
    # fails at checkLinkTargets. This runs BEFORE that check.
    home.activation.cleanupPhotogimpOrphanFiles =
      lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        STAMP="$HOME/.local/share/vexos/.photogimp-orphan-cleanup-done"
        if [ -f "$STAMP" ]; then
          $VERBOSE_ECHO "PhotoGIMP: orphan cleanup already done, skipping"
        else
          DESKTOP_FILE="$HOME/.local/share/applications/org.gimp.GIMP.desktop"
          if [ -f "$DESKTOP_FILE" ] && [ ! -L "$DESKTOP_FILE" ]; then
            $VERBOSE_ECHO "PhotoGIMP: removing orphaned desktop file"
            $DRY_RUN_CMD rm -f "$DESKTOP_FILE"
          fi

          for size in 16x16 32x32 48x48 64x64 128x128 256x256 512x512; do
            ICON_FILE="$HOME/.local/share/icons/hicolor/$size/apps/photogimp.png"
            if [ -f "$ICON_FILE" ] && [ ! -L "$ICON_FILE" ]; then
              $VERBOSE_ECHO "PhotoGIMP: removing orphaned icon $size/apps/photogimp.png"
              $DRY_RUN_CMD rm -f "$ICON_FILE"
            fi
          done

          for stray in \
            "$HOME/.local/share/icons/hicolor/photogimp.png" \
            "$HOME/.local/share/icons/hicolor/256x256/256x256.png"; do
            if [ -f "$stray" ] && [ ! -L "$stray" ]; then
              $VERBOSE_ECHO "PhotoGIMP: removing stray file $stray"
              $DRY_RUN_CMD rm -f "$stray"
            fi
          done

          $DRY_RUN_CMD mkdir -p "$HOME/.local/share/vexos"
          $DRY_RUN_CMD touch "$STAMP"
        fi
      '';

    # ── Step 2: copy GIMP plugin/config files ──────────────────────────────
    # Uses a version sentinel so this only runs on first install or version bump,
    # preserving any runtime GIMP customisations the user makes between rebuilds.
    home.activation.installPhotoGIMP = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      GIMP_CONFIG="$HOME/.config/GIMP/3.0"
      VERSION_FILE="$GIMP_CONFIG/.photogimp-version"

      if [ ! -f "$VERSION_FILE" ] || \
         [ "$(${pkgs.coreutils}/bin/cat "$VERSION_FILE" 2>/dev/null)" != "${photogimpVersion}" ]; then
        $VERBOSE_ECHO "PhotoGIMP: installing version ${photogimpVersion} config files"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$GIMP_CONFIG"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -rf \
          ${photogimp}/.var/app/org.gimp.GIMP/config/GIMP/3.0/. \
          "$GIMP_CONFIG/"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod -R u+w "$GIMP_CONFIG/"
        if [ -z "$DRY_RUN_CMD" ]; then
          ${pkgs.coreutils}/bin/printf '%s' "${photogimpVersion}" > "$VERSION_FILE"
        fi
      fi
    '';

    # ── Step 3: refresh icon cache and desktop database ────────────────────
    # Without these GNOME won't show the photogimp icon or renamed launcher
    # until the next full session restart.
    home.activation.refreshPhotoGIMPDesktopIntegration =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ICON_DIR="$HOME/.local/share/icons/hicolor"
        APP_DIR="$HOME/.local/share/applications"

        if [ -d "$ICON_DIR" ]; then
          $VERBOSE_ECHO "PhotoGIMP: updating hicolor icon cache"
          $DRY_RUN_CMD ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t "$ICON_DIR"
        fi

        if [ -d "$APP_DIR" ]; then
          $VERBOSE_ECHO "PhotoGIMP: updating desktop database"
          $DRY_RUN_CMD ${pkgs.desktop-file-utils}/bin/update-desktop-database "$APP_DIR"
        fi
      '';

    # ── Step 4: install PhotoGIMP icons into user hicolor theme ────────────
    # recursive = true creates per-file symlinks, safe alongside other icon themes.
    xdg.dataFile."icons/hicolor" = {
      source    = photogimp + "/.local/share/icons/hicolor";
      recursive = true;
    };

    # ── Step 5: override GIMP .desktop with PhotoGIMP branding ────────────
    # Uses xdg.dataFile + text instead of xdg.desktopEntries so the file lands
    # at ~/.local/share/applications/org.gimp.GIMP.desktop as a file-level
    # symlink. GNOME's inotify watcher reliably detects file-level symlink
    # changes (vs. directory-level profile generation swaps used by
    # xdg.desktopEntries), and GLib always checks XDG_DATA_HOME/applications/
    # before any XDG_DATA_DIRS entry, so this override takes precedence over
    # the Flatpak-exported .desktop in /var/lib/flatpak/exports/share/applications/.
    # X-Flatpak is required by GNOME Shell 46+ to associate the running Flatpak
    # window with this .desktop entry for the taskbar/app indicator.
    xdg.dataFile."applications/org.gimp.GIMP.desktop" = {
      text = ''
        [Desktop Entry]
        Type=Application
        Name=PhotoGIMP
        GenericName=Image Editor
        Comment=Create images and edit photographs
        Exec=flatpak run org.gimp.GIMP %U
        Icon=photogimp
        Terminal=false
        StartupNotify=true
        Categories=Graphics;2DGraphics;RasterGraphics;GTK;
        MimeType=image/bmp;image/g3fax;image/gif;image/jpeg;image/png;image/tiff;image/webp;image/heif;image/heic;image/svg+xml;image/x-bmp;image/x-compressed-xcf;image/x-exr;image/x-gimp-gbr;image/x-gimp-gih;image/x-gimp-pat;image/x-icon;image/x-pcx;image/x-portable-anymap;image/x-portable-bitmap;image/x-portable-graymap;image/x-portable-pixmap;image/x-psd;image/x-sgi;image/x-tga;image/x-wmf;image/x-xcf;image/x-xcursor;image/x-xpixmap;image/x-xwindowdump;image/jp2;application/pdf;application/postscript;
        X-Flatpak=org.gimp.GIMP
      '';
    };
  };
}
