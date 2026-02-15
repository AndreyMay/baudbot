#!/bin/bash
# Hornet Agent Launcher
# Run as: sudo -u hornet_agent /home/hornet_agent/start.sh

set -euo pipefail
cd ~

# Set PATH
export PATH="$HOME/opt/node-v22.14.0-linux-x64/bin:$PATH"

# Load secrets
set -a
source ~/.config/.env
set +a

# Start control-agent (it will spawn dev-agent as needed)
pi --name control-agent --skill control-agent
