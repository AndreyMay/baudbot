#!/bin/bash
# Security audit for Hornet agent infrastructure
# Run as hornet_agent or admin user to check security posture
#
# Usage: ~/hornet/bin/security-audit.sh
#        sudo -u hornet_agent ~/hornet/bin/security-audit.sh

set -euo pipefail

HORNET_HOME="${HORNET_HOME:-/home/hornet_agent}"

# Counters
critical=0
warn=0
info=0
pass=0

finding() {
  local severity="$1"
  local title="$2"
  local detail="$3"

  case "$severity" in
    CRITICAL) echo "  ❌ CRITICAL: $title"; critical=$((critical + 1)) ;;
    WARN)     echo "  ⚠️  WARN:     $title"; warn=$((warn + 1)) ;;
    INFO)     echo "  ℹ️  INFO:     $title"; info=$((info + 1)) ;;
  esac
  [ -n "$detail" ] && echo "              $detail"
}

ok() {
  echo "  ✅ PASS:     $1"
  pass=$((pass + 1))
}

echo ""
echo "🔒 Hornet Security Audit"
echo "========================"
echo ""

# ── Docker group ─────────────────────────────────────────────────────────────

echo "Docker Access"
if id hornet_agent 2>/dev/null | grep -q '(docker)'; then
  finding "CRITICAL" "hornet_agent is in docker group" \
    "Can bypass hornet-docker wrapper via /usr/bin/docker directly"
else
  ok "hornet_agent not in docker group"
fi

if [ -f /usr/local/bin/hornet-docker ]; then
  ok "Docker wrapper installed at /usr/local/bin/hornet-docker"
else
  finding "WARN" "Docker wrapper not found" \
    "Expected /usr/local/bin/hornet-docker"
fi
echo ""

# ── Filesystem permissions ───────────────────────────────────────────────────

echo "Filesystem Permissions"

check_perms() {
  local path="$1"
  local expected="$2"
  local desc="$3"
  if [ ! -e "$path" ]; then
    return
  fi
  actual=$(stat -c '%a' "$path" 2>/dev/null || echo "???")
  if [ "$actual" = "$expected" ]; then
    ok "$desc ($actual)"
  else
    local sev="WARN"
    # Group/world readable secrets or state = critical
    if [ "$expected" = "600" ] || [ "$expected" = "700" ]; then
      # Check if actually group/world readable
      if [ $((0$actual & 044)) -ne 0 ]; then
        sev="CRITICAL"
      fi
    fi
    finding "$sev" "$desc is $actual (expected $expected)" "$path"
  fi
}

check_perms "$HORNET_HOME/.config/.env" "600" "Secrets file"
check_perms "$HORNET_HOME/.ssh" "700" "SSH directory"
check_perms "$HORNET_HOME/.pi" "700" "Pi state directory"
check_perms "$HORNET_HOME/.pi/agent" "700" "Pi agent directory"
check_perms "$HORNET_HOME/.pi/session-control" "700" "Pi session-control directory"
check_perms "$HORNET_HOME/.pi/agent/settings.json" "600" "Pi settings"

# Check session logs
if [ -d "$HORNET_HOME/.pi/agent/sessions" ]; then
  leaky_logs=$(find "$HORNET_HOME/.pi/agent/sessions" -name '*.jsonl' -perm /044 2>/dev/null | wc -l)
  if [ "$leaky_logs" -gt 0 ]; then
    finding "WARN" "$leaky_logs session log(s) are group/world-readable" \
      "Run: ~/hornet/bin/harden-permissions.sh"
  else
    ok "Session logs are owner-only"
  fi
fi

# Check control sockets
if [ -d "$HORNET_HOME/.pi/session-control" ]; then
  leaky_socks=$(find "$HORNET_HOME/.pi/session-control" -name '*.sock' -perm /044 2>/dev/null | wc -l)
  if [ "$leaky_socks" -gt 0 ]; then
    finding "WARN" "$leaky_socks control socket(s) are group/world-accessible" \
      "Other users could send commands to running agent sessions"
  else
    ok "Control sockets are owner-only"
  fi
fi
echo ""

# ── Secrets in readable files ────────────────────────────────────────────────

echo "Secret Exposure"
# Check for secrets in group-readable files (skip .env which should be 600)
secret_patterns='(sk-[a-zA-Z0-9]{20,}|xoxb-|xapp-|ghp_[a-zA-Z0-9]{36}|AKIA[A-Z0-9]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY)'
leaked_files=$(find "$HORNET_HOME" -maxdepth 3 \
  -not -path '*/.ssh/*' \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/.config/.env' \
  -not -path '*/security-audit.sh' \
  -not -path '*/.env.schema' \
  -not -name '*.md' \
  -not -name 'bridge.mjs' \
  -type f -perm /044 \
  -exec grep -l -E "$secret_patterns" {} \; 2>/dev/null | head -5)

if [ -n "$leaked_files" ]; then
  finding "CRITICAL" "Possible secrets in group/world-readable files:" ""
  echo "$leaked_files" | while read -r f; do echo "              $f"; done
else
  ok "No secrets found in readable files"
fi

# Check git config for tokens
if [ -f "$HORNET_HOME/.gitconfig" ]; then
  if grep -qiE '(token|password|secret)' "$HORNET_HOME/.gitconfig" 2>/dev/null; then
    finding "WARN" "Possible credentials in .gitconfig" "$HORNET_HOME/.gitconfig"
  else
    ok "No credentials in .gitconfig"
  fi
fi
echo ""

# ── Network ──────────────────────────────────────────────────────────────────

echo "Network"

# Check if bridge is bound to localhost only
bridge_bind=$(ss -tlnp 2>/dev/null | grep ':7890' | awk '{print $4}' | head -1)
if [ -n "$bridge_bind" ]; then
  if echo "$bridge_bind" | grep -q '127.0.0.1'; then
    ok "Slack bridge bound to 127.0.0.1:7890"
  else
    finding "CRITICAL" "Slack bridge bound to $bridge_bind (not localhost!)" \
      "Should bind to 127.0.0.1 only"
  fi
else
  finding "INFO" "Slack bridge not running" ""
fi

# Check firewall rules
if command -v iptables &>/dev/null; then
  if iptables -L HORNET_OUTPUT -n 2>/dev/null | grep -q 'DROP'; then
    ok "Firewall rules active (HORNET_OUTPUT chain)"
  else
    finding "WARN" "No firewall rules for hornet_agent" \
      "Run: sudo ~/hornet/bin/setup-firewall.sh"
  fi
fi

# Check for unexpected listeners
if [ "$(id -u)" = "$(id -u hornet_agent 2>/dev/null)" ]; then
  listeners=$(ss -tlnp 2>/dev/null | grep -v '127.0.0.1' | grep -v '::1' | grep -v 'LISTEN' | wc -l)
  # This is a rough check — skip if not running as hornet_agent
fi
echo ""

# ── Ollama ───────────────────────────────────────────────────────────────────

echo "Services"
if ss -tlnp 2>/dev/null | grep -q ':11434'; then
  bind_addr=$(ss -tlnp 2>/dev/null | grep ':11434' | awk '{print $4}' | head -1)
  if echo "$bind_addr" | grep -qE '(0\.0\.0\.0|\*|::)'; then
    finding "INFO" "Ollama listening on $bind_addr (all interfaces)" \
      "Consider binding to 127.0.0.1 if not needed externally"
  else
    ok "Ollama bound to $bind_addr"
  fi
fi
echo ""

# ── Summary ──────────────────────────────────────────────────────────────────

echo "Summary"
echo "───────"
echo "  ✅ Pass:     $pass"
echo "  ❌ Critical: $critical"
echo "  ⚠️  Warn:     $warn"
echo "  ℹ️  Info:     $info"
echo ""

if [ "$critical" -gt 0 ]; then
  echo "🚨 $critical critical finding(s) — fix immediately!"
  exit 2
elif [ "$warn" -gt 0 ]; then
  echo "⚠️  $warn warning(s) — review recommended."
  exit 1
else
  echo "✅ All checks passed."
  exit 0
fi
