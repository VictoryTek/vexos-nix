# modules/security-server.nix
# Server-only security additions on top of modules/security.nix.
#
# Imported ONLY by configuration-server.nix and configuration-headless-server.nix.
# Per the project's Option B pattern, this file contains NO lib.mkIf gating —
# its presence in the import list is what makes it apply.
#
# What it adds:
#   - auditd: kernel audit framework. AppArmor denials are routed through
#     the audit subsystem; without auditd they only land in dmesg/journald
#     with no structured retention. On servers we want persistent, parsable
#     records of policy violations.
#   - audit ruleset: CIS-aligned baseline covering time changes, execve,
#     mount/umount, kernel module load/unload, sudoers and sshd_config writes.
#   - fail2ban: brute-force mitigation for SSH and Cockpit. Enabled by default
#     on server roles because Cockpit and optional Samba/NFS file sharing are
#     usually LAN-exposed via explicit firewall rules in modules/server/cockpit.nix.
#     These services rely on PAM/system accounts, so SSH brute-force protection
#     is the minimum required baseline.
{ ... }:
{
  # Kernel audit daemon: required for proper AppArmor denial logging on
  # long-running hosts. Pulls in the auditd systemd unit and rotates
  # /var/log/audit/audit.log via its own logrotate.
  security.auditd.enable = true;

  # Audit framework configuration: enable rule loading and install a
  # CIS NixOS-aligned baseline that captures AppArmor STATUS/DENIED records
  # along with privilege escalation, time changes, exec, mount, and kernel
  # module events.
  security.audit = {
    enable = true;
    rules = [
      # Time changes — useful for forensic timeline reconstruction
      "-a always,exit -F arch=b64 -S adjtimex,settimeofday -k time_change"
      # All exec calls — noisy but critical for audit trails on servers
      "-a always,exit -F arch=b64 -S execve -k exec"
      # Mount and unmount events
      "-a always,exit -F arch=b64 -S mount -S umount2 -k mounts"
      # Kernel module load/unload
      "-a always,exit -F arch=b64 -S init_module -S delete_module -S finit_module -k modules"
      # Privileged file writes
      "-w /etc/sudoers -p wa -k sudoers"
      "-w /etc/ssh/sshd_config -p wa -k sshd_config"
    ];
  };

  # Fail2ban: brute-force mitigation for SSH on server roles. Samba and NFS
  # do not have fail2ban filters in nixpkgs but benefit from SSH protection
  # since they share the same system accounts.
  #
  # NixOS automatically enables the sshd jail when both services.fail2ban
  # and services.openssh are enabled. The top-level maxretry / bantime
  # settings below apply to all jails as defaults.
  #
  # Cockpit jail is intentionally absent: Cockpit's PAM logs do not include
  # the remote client IP (upstream bug cockpit-project/cockpit#722, open since
  # 2014), making IP-based banning impossible. A jail with no IP is inert and
  # causes fail2ban to fail on startup if the filter file is missing.
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    # Recidive: escalating ban for repeat offenders across all jails.
    # Bans for 1 week after 3 bans in 1 day.
    jails.recidive = ''
      enabled   = true
      filter    = recidive
      maxretry  = 3
      findtime  = 86400
      bantime   = 604800
    '';
  };
}

