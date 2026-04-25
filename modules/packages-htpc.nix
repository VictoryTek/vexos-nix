# modules/packages-htpc.nix
# HTPC-specific media packages: full GStreamer codec stack, hardware-accelerated
# media players, and HDMI-CEC integration.
# Imported only by configuration-htpc.nix.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # ── Media players ─────────────────────────────────────────────────────
    vlc   # Comprehensive player; handles virtually every container and codec
    mpv   # Lightweight GPU-accelerated player

    # ── GStreamer full plugin set ─────────────────────────────────────────
    # Required for GNOME media apps (Totem), web browsers, and any
    # application using GStreamer for video/audio decoding.
    gst_all_1.gst-plugins-base   # Core elements: ogg, vorbis, theora, raw video
    gst_all_1.gst-plugins-good   # VP8/VP9, AAC, FLAC, JPEG
    gst_all_1.gst-plugins-bad    # H.264/H.265, AV1, Opus; includes VA-API elements
    gst_all_1.gst-plugins-ugly   # MP3, MPEG-2, AC3 (patent-encumbered but FOSS)
    gst_all_1.gst-libav          # ffmpeg bridge — broadest codec compatibility

    # ── HDMI-CEC ─────────────────────────────────────────────────────────
    libcec   # HDMI-CEC library + cec-client for TV/AVR control via HDMI
  ];
}
