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
#   - audit ruleset: minimal "log AppArmor denials" baseline. Custom rules
#     can be appended in role config later if needed.
{ ... }:
{
  # Kernel audit daemon: required for proper AppArmor denial logging on
  # long-running hosts. Pulls in the auditd systemd unit and rotates
  # /var/log/audit/audit.log via its own logrotate.
  security.auditd.enable = true;

  # Audit framework configuration: enable rule loading and install a
  # minimal baseline that captures AppArmor STATUS and DENIED records
  # along with privilege escalation events. Servers benefit from this
  # context; desktops would just generate noise.
  security.audit = {
    enable = true;
    rules = [
      # AppArmor status changes (profile loads, mode switches)
      "-w /etc/apparmor.d/ -p wa -k apparmor_policy"
      # Time changes — useful for forensic timeline reconstruction
      "-a always,exit -F arch=b64 -S adjtimex,settimeofday -k time_change"
    ];
  };
}
