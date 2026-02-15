# Hornet

Autonomous coding agent running as an isolated Linux user.

## Architecture

```
hornet_agent (uid)
├── ~/.config/.env          # secrets (not in repo)
├── ~/.ssh/                 # SSH key for GitHub (not in repo)
├── ~/.pi/agent/
│   ├── settings.json       # pi config
│   ├── skills/ → ~/hornet/pi/skills/
│   └── extensions/ → ~/hornet/pi/extensions/
└── ~/hornet/               # this repo
    ├── start.sh            # launch script
    ├── setup.sh            # install from scratch
    ├── SECURITY.md         # trust boundaries & threat model
    ├── bin/
    │   ├── hornet-docker         # Docker wrapper (blocks escalation)
    │   ├── harden-permissions.sh # Lock down pi state files
    │   ├── security-audit.sh     # Check security posture
    │   └── setup-firewall.sh     # Port-based network lockdown
    ├── slack-bridge/
    │   ├── bridge.mjs            # Slack ↔ pi bridge (Socket Mode)
    │   └── package.json
    └── pi/
        ├── settings.json
        ├── skills/
        │   ├── control-agent/SKILL.md
        │   └── dev-agent/SKILL.md
        └── extensions/
            ├── zen-provider.ts
            ├── auto-name.ts
            ├── control.ts
            ├── todos.ts
            ├── agentmail/
            ├── email-monitor/
            ├── kernel/
            ├── files.ts
            ├── context.ts
            └── loop.ts
```

## Identity

| | |
|---|---|
| **Unix user** | `hornet_agent` |
| **GitHub** | [hornet-fw](https://github.com/hornet-fw) |
| **Email** | hornet@modem.codes → hornet@agentmail.to |
| **LLM** | Claude Opus 4.6 via OpenCode Zen |
| **Pi agent** | control-agent (spawns dev-agent) |

## Security

See [SECURITY.md](SECURITY.md) for full trust boundaries and threat model.

- Runs as unprivileged `hornet_agent` user — no sudo
- Cannot read admin home directory
- Docker access via wrapper that blocks privilege escalation
- External content (Slack, email) wrapped with security boundaries before reaching LLM
- Prompt injection detection logging in the Slack bridge
- Secrets in `~/.config/.env` (600 perms, not in repo)
- SSH key owner-only (700/600 perms)

### Security Scripts

```bash
# Check security posture
~/hornet/bin/security-audit.sh

# Lock down pi state file permissions (run on startup)
~/hornet/bin/harden-permissions.sh

# Apply port-based network restrictions (run as root)
sudo ~/hornet/bin/setup-firewall.sh
```

## Setup

```bash
# Clone the repo (need SSH key + known_hosts first)
sudo su - hornet_agent -c 'ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null'
sudo su - hornet_agent -c 'git clone git@github.com:modem-dev/hornet.git ~/hornet'

# Run setup (as root)
sudo bash /home/hornet_agent/hornet/setup.sh <admin_username>

# Add secrets
sudo su - hornet_agent -c 'vim ~/.config/.env'
# GITHUB_TOKEN=...
# OPENCODE_ZEN_API_KEY=...
# AGENTMAIL_API_KEY=...
# KERNEL_API_KEY=...
# HORNET_SECRET=...
```

## Launch

```bash
sudo -u hornet_agent /home/hornet_agent/hornet/start.sh
```

This starts the **control-agent**, which automatically spawns a **dev-agent** in a tmux session.

## Monitoring

Hornet uses tmux to manage sub-agent sessions. All commands run as `hornet_agent`.

### List sessions

```bash
sudo -u hornet_agent tmux ls
```

### Watch the control-agent

The control-agent runs in the foreground terminal where you launched `start.sh`.

### Watch the dev-agent

```bash
sudo -u hornet_agent tmux attach -t dev-agent
```

Detach without killing: `Ctrl+b` then `d`

### Kill everything

```bash
# Kill all hornet processes (pi sessions + tmux)
sudo -u hornet_agent pkill -u hornet_agent
```

### Restart

```bash
sudo -u hornet_agent pkill -u hornet_agent
sudo -u hornet_agent /home/hornet_agent/hornet/start.sh
```

## Updating

Changes to skills, extensions, or config are tracked in this repo. After pulling:

```bash
# settings.json needs to be copied (not symlinked, pi writes to it)
sudo -u hornet_agent cp ~/hornet/pi/settings.json ~/.pi/agent/settings.json

# Extension deps (if package.json changed)
sudo -u hornet_agent bash -c '
  export PATH=~/opt/node-v22.14.0-linux-x64/bin:$PATH
  cd ~/hornet/pi/extensions/kernel && npm install
  cd ~/hornet/pi/extensions/agentmail && npm install
'
```

Skills and extensions are symlinked and update automatically.
