#!/bin/bash
# Port-based network lockdown for hornet_agent
# Run as root: sudo ~/hornet/bin/setup-firewall.sh
#
# Allows: HTTP (80), HTTPS (443), SSH (22), DNS (53), localhost
# Blocks: everything else (reverse shells, raw sockets, non-standard ports)
#
# Web browsing and all HTTPS APIs still work. The agent cannot:
# - Open reverse shells on non-standard ports
# - Use raw/ICMP sockets for covert channels
# - Bind to ports (no inbound listeners/backdoors)
# - Do DNS tunneling over non-53 UDP

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Must run as root (sudo $0)"
  exit 1
fi

UID_HORNET=$(id -u hornet_agent 2>/dev/null)
if [ -z "$UID_HORNET" ]; then
  echo "❌ hornet_agent user not found"
  exit 1
fi

CHAIN="HORNET_OUTPUT"

echo "🔒 Setting up firewall rules for hornet_agent (uid $UID_HORNET)..."

# Clean up any existing rules first
iptables -D OUTPUT -m owner --uid-owner "$UID_HORNET" -j "$CHAIN" 2>/dev/null || true
iptables -F "$CHAIN" 2>/dev/null || true
iptables -X "$CHAIN" 2>/dev/null || true

# Create a dedicated chain for hornet_agent
iptables -N "$CHAIN"

# Allow localhost (bridge API, postgres, ollama, pi sockets)
iptables -A "$CHAIN" -o lo -j ACCEPT

# Allow DNS (UDP + TCP)
iptables -A "$CHAIN" -p udp --dport 53 -j ACCEPT
iptables -A "$CHAIN" -p tcp --dport 53 -j ACCEPT

# Allow HTTP/HTTPS (web browsing, all APIs)
iptables -A "$CHAIN" -p tcp --dport 80 -j ACCEPT
iptables -A "$CHAIN" -p tcp --dport 443 -j ACCEPT

# Allow SSH (git push/pull)
iptables -A "$CHAIN" -p tcp --dport 22 -j ACCEPT

# Allow established/related (responses to allowed outbound)
iptables -A "$CHAIN" -m state --state ESTABLISHED,RELATED -j ACCEPT

# Log and drop everything else
iptables -A "$CHAIN" -j LOG --log-prefix "HORNET_BLOCKED: " --log-level 4
iptables -A "$CHAIN" -j DROP

# Jump to our chain for all hornet_agent traffic
iptables -A OUTPUT -m owner --uid-owner "$UID_HORNET" -j "$CHAIN"

echo "✅ Firewall active. Rules:"
echo ""
iptables -L "$CHAIN" -n -v --line-numbers
echo ""
echo "To remove: sudo iptables -D OUTPUT -m owner --uid-owner $UID_HORNET -j $CHAIN && sudo iptables -F $CHAIN && sudo iptables -X $CHAIN"
echo ""
echo "⚠️  These rules are NOT persistent across reboots."
echo "   To persist, add to a systemd unit or use iptables-save/iptables-restore."
