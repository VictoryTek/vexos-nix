# modules/audio.nix
# PipeWire audio stack with low-latency tuning, ALSA/PulseAudio/JACK compat,
# rtkit realtime scheduling, and Bluetooth high-quality codec support.
{ config, pkgs, lib, ... }:
{
  # rtkit: allows PipeWire and audio threads to use realtime scheduling
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;

    # ── Compatibility layers ────────────────────────────────────────────────
    alsa.enable = true;
    alsa.support32Bit = true; # required for 32-bit Wine/Proton audio paths
    pulse.enable = true;      # PulseAudio compatibility
    jack.enable = true;       # JACK compatibility (useful for pro audio / DAWs)

    # ── Low-latency tuning ─────────────────────────────────────────────────
    # Native PipeWire quantum/rate config — no external module required.
    # quantum=64 at 48 kHz gives ~1.33 ms latency; suits all roles.
    # Increase quantum to 128 or 256 if audio crackling occurs.
    extraConfig.pipewire."92-low-latency" = {
      context.properties = {
        "default.clock.rate"        = 48000;
        "default.clock.quantum"     = 64;
        "default.clock.min-quantum" = 64;
        "default.clock.max-quantum" = 8192;
      };
    };

    # ── WirePlumber: Bluetooth high-quality codecs ─────────────────────────
    # Enables SBC-XQ (higher-quality SBC), mSBC, and hardware volume support.
    wireplumber.extraConfig."10-bluez" = {
      "monitor.bluez.properties" = {
        "bluez5.enable-sbc-xq"    = true;
        "bluez5.enable-msbc"      = true;
        "bluez5.enable-hw-volume" = true;
        "bluez5.codecs" = [ "aac" "ldac" "aptx" "aptx_hd" ];
        "bluez5.roles" = [
          "hsp_hs" "hsp_ag" "hfp_hf" "hfp_ag"
        ];
      };
    };
  };

  # Grant nimda raw ALSA access (optional alongside PipeWire).
  users.users.${config.vexos.user.name}.extraGroups = [ "audio" ];
}
