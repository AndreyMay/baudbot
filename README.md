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
    ├── bin/hornet-docker    # Docker wrapper (blocks escalation)
    └── pi/
        ├── settings.json
        ├── skills/
        │   ├── control-agent/SKILL.md
        │   └── dev-agent/SKILL.md
        └── extensions/
            └── zen-provider.ts
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

- Runs as unprivileged `hornet_agent` user — no sudo
- Cannot read admin home directory
- Docker access via wrapper that blocks:
  - `--privileged`, `--pid=host`, `--net=host`
  - `--cap-add=ALL`, `SYS_ADMIN`, `SYS_PTRACE`
  - Mounting `/`, `/etc`, `/root`, admin home, docker socket
- Secrets in `~/.config/.env` (600 perms, not in repo)
- SSH key owner-only (700/600 perms)
- Separate pi sessions — cannot see/control admin's pi

## Setup

```bash
# Clone the repo
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

## Updating

Changes to skills, extensions, or config are tracked in this repo. After pulling:

```bash
# settings.json needs to be copied (not symlinked, pi writes to it)
sudo -u hornet_agent cp ~/hornet/pi/settings.json ~/.pi/agent/settings.json
```

Skills and extensions are symlinked and update automatically.
