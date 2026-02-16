#!/bin/bash
# Hornet Agent Launcher
# Run as: sudo -u hornet_agent ~/runtime/start.sh
#
# The agent runs entirely from deployed copies — no source repo access needed:
#   ~/.pi/agent/extensions/  ← pi extensions
#   ~/.pi/agent/skills/      ← operational skills
#   ~/runtime/slack-bridge/  ← bridge process
#   ~/runtime/bin/           ← utility scripts
#
# To update, admin edits source and runs deploy.sh.

set -euo pipefail
cd ~

# Set PATH
export PATH="$HOME/opt/node-v22.14.0-linux-x64/bin:$PATH"

# Load secrets
set -a
source ~/.config/.env
set +a

# Harden file permissions (pi defaults are too permissive)
umask 077
~/runtime/bin/harden-permissions.sh

# Redact any secrets that leaked into session logs
~/runtime/bin/redact-logs.sh 2>/dev/null || true

# Set session name (read by auto-name.ts extension)
export PI_SESSION_NAME="control-agent"

# Start control-agent
# --session-control: enables inter-session communication (handled by control.ts extension)
pi --session-control --skill ~/.pi/agent/skills/control-agent "/skill:control-agent"
