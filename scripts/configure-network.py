#!/usr/bin/env python3
"""Uncomment the wired-static NetworkManager profile block in modules/network.nix
and fill in IP / gateway / DNS placeholders.

Usage:
    python3 configure-network.py <network.nix path> <addr/prefix> <gateway> <dns>

Example:
    python3 configure-network.py modules/network.nix 192.168.1.10/24 192.168.1.1 1.1.1.1
"""
import sys
import re

path, addr, gw, dns = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(path, 'r') as f:
    text = f.read()

# Strip leading '#   ' or '  # ' from the wired-static block lines
# The block is delimited by the first '# networking.networkmanager...'
# comment line and the closing '# };' line.
def uncomment_block(m):
    block = m.group(0)
    # Remove the comment prefix '  # ' from each line inside the block
    block = re.sub(r'^  # ', '  ', block, flags=re.MULTILINE)
    return block

text = re.sub(
    r'  # networking\.networkmanager\.ensureProfiles\.profiles\."wired-static".*?  # \};',
    uncomment_block,
    text,
    flags=re.DOTALL
)

# Fill in placeholders
text = text.replace('PLACEHOLDER_IP/PLACEHOLDER_PREFIX', addr)
text = text.replace('PLACEHOLDER_GATEWAY', gw)
text = text.replace('PLACEHOLDER_DNS1;PLACEHOLDER_DNS2', dns)
# Handle single-DNS case where the value has no semicolon
text = re.sub(r'PLACEHOLDER_DNS1', dns, text)

with open(path, 'w') as f:
    f.write(text)

print("Done.")

if __name__ == "__main__":
    pass
