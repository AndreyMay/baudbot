#!/bin/bash
# Deploy extensions and bridge from hornet source to agent runtime.
#
# Invoked by the admin after editing ~/hornet/ source:
#   sudo -u hornet_agent ~/hornet/bin/deploy.sh
#   sudo -u hornet_agent ~/hornet/bin/deploy.sh --dry-run
#
# Runs as hornet_agent so it can write to ~/.pi/agent/ and ~/runtime/.
# Protected security files are made read-only (chmod a-w) after copy.
# The agent owns these files but cannot write to them; tool-guard blocks
# chmod at the pi level, and the source repo is always available to
# re-deploy if runtime copies are tampered with.
#
# For stronger protection (root-owned runtime files, bind mount), run
# setup.sh as root — it calls this script then applies root-level hardening.

set -euo pipefail

HORNET_SRC="$HOME/hornet"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
  esac
done

log() { echo "  $1"; }

# Security-critical files — deployed read-only (chmod a-w)
PROTECTED_EXTENSIONS=(tool-guard.ts tool-guard.test.mjs)
PROTECTED_BRIDGE_FILES=(security.mjs security.test.mjs)

# ── Extensions ───────────────────────────────────────────────────────────────

echo "Deploying extensions..."

EXT_SRC="$HORNET_SRC/pi/extensions"
EXT_DEST="$HOME/.pi/agent/extensions"

[ "$DRY_RUN" -eq 0 ] && mkdir -p "$EXT_DEST"

for ext in "$EXT_SRC"/*; do
  base=$(basename "$ext")
  [ "$base" = "node_modules" ] && continue

  if [ -d "$ext" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
      # Make destination writable first (source files may have been a-w)
      if [ -d "$EXT_DEST/$base" ]; then
        find "$EXT_DEST/$base" -type d -exec chmod u+w {} + 2>/dev/null || true
        find "$EXT_DEST/$base" -type f -exec chmod u+w {} + 2>/dev/null || true
      fi
      mkdir -p "$EXT_DEST/$base"
      cp -a "$ext/." "$EXT_DEST/$base/"
      # Ensure everything is writable (cp -a preserves source's a-w perms)
      find "$EXT_DEST/$base" -type d -exec chmod u+w {} + 2>/dev/null || true
      find "$EXT_DEST/$base" -type f -exec chmod u+w {} + 2>/dev/null || true
      log "✓ $base/"
    else
      log "would copy: $base/"
    fi
    continue
  fi

  # Check if protected
  is_protected=0
  for pf in "${PROTECTED_EXTENSIONS[@]}"; do
    [ "$base" = "$pf" ] && is_protected=1 && break
  done

  if [ "$DRY_RUN" -eq 0 ]; then
    # Unlock destination if it exists and is read-only (from previous deploy)
    [ -f "$EXT_DEST/$base" ] && chmod u+w "$EXT_DEST/$base" 2>/dev/null || true
    cp -a "$ext" "$EXT_DEST/$base"
    if [ "$is_protected" -eq 1 ]; then
      chmod a-w "$EXT_DEST/$base"
      log "✓ $base (read-only)"
    else
      chmod u+w "$EXT_DEST/$base"
      log "✓ $base"
    fi
  else
    if [ "$is_protected" -eq 1 ]; then
      log "would copy: $base (read-only)"
    else
      log "would copy: $base"
    fi
  fi
done

# ── Skills ───────────────────────────────────────────────────────────────────

echo "Deploying skills..."

SKILLS_SRC="$HORNET_SRC/pi/skills"
SKILLS_DEST="$HOME/.pi/agent/skills"

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$SKILLS_DEST"
  cp -a "$SKILLS_SRC/." "$SKILLS_DEST/"
  log "✓ skills/"
else
  log "would copy: skills/"
fi

# ── Slack Bridge ─────────────────────────────────────────────────────────────

echo "Deploying slack-bridge..."

BRIDGE_SRC="$HORNET_SRC/slack-bridge"
BRIDGE_DEST="$HOME/runtime/slack-bridge"

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$BRIDGE_DEST"

  # Unlock protected files before bulk copy (so cp can overwrite them)
  for pf in "${PROTECTED_BRIDGE_FILES[@]}"; do
    [ -f "$BRIDGE_DEST/$pf" ] && chmod u+w "$BRIDGE_DEST/$pf" 2>/dev/null || true
  done

  cp -a "$BRIDGE_SRC/." "$BRIDGE_DEST/"

  # Lock protected files read-only
  for pf in "${PROTECTED_BRIDGE_FILES[@]}"; do
    [ -f "$BRIDGE_DEST/$pf" ] && chmod a-w "$BRIDGE_DEST/$pf" && log "✓ $pf (read-only)"
  done

  # Agent-modifiable files stay writable
  [ -f "$BRIDGE_DEST/bridge.mjs" ] && chmod u+w "$BRIDGE_DEST/bridge.mjs" && log "✓ bridge.mjs"

  log "✓ node_modules/ + package files"
else
  log "would copy: slack-bridge/"
fi

# ── Settings ─────────────────────────────────────────────────────────────────

echo "Deploying settings..."

if [ -f "$HORNET_SRC/pi/settings.json" ]; then
  if [ "$DRY_RUN" -eq 0 ]; then
    cp "$HORNET_SRC/pi/settings.json" "$HOME/.pi/agent/settings.json"
    chmod 600 "$HOME/.pi/agent/settings.json"
    log "✓ settings.json"
  else
    log "would copy: settings.json"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
if [ "$DRY_RUN" -eq 1 ]; then
  echo "🔍 Dry run — no changes made."
else
  echo "✅ Deployed. Protected files are read-only."
  echo ""
  echo "If the bridge is running, restart it:"
  echo "  sudo -u hornet_agent bash -c 'cd ~/runtime/slack-bridge && node bridge.mjs'"
fi
