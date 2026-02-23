#!/bin/bash
# Focused tests for bin/doctor.sh dependency reporting.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCTOR_SCRIPT="$REPO_ROOT/bin/doctor.sh"

TOTAL=0
PASSED=0
FAILED=0

run_test() {
  local name="$1"
  shift
  local out

  TOTAL=$((TOTAL + 1))
  printf "  %-45s " "$name"

  out="$(mktemp /tmp/baudbot-doctor-test-output.XXXXXX)"
  if "$@" >"$out" 2>&1; then
    echo "✓"
    PASSED=$((PASSED + 1))
  else
    echo "✗ FAILED"
    tail -40 "$out" | sed 's/^/    /'
    FAILED=$((FAILED + 1))
  fi
  rm -f "$out"
}

make_fake_commands() {
  local fakebin="$1"
  local home_dir="$2"
  local claude_probe="$3"
  mkdir -p "$fakebin"
  mkdir -p "$home_dir/.local/bin"

  cat > "$fakebin/sudo" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "-u" ] && [ "$#" -ge 3 ]; then
  shift 2
fi
exec "$@"
EOF

  cat > "$fakebin/curl" <<'EOF'
#!/bin/bash
echo "400"
EOF

  cat > "$fakebin/rg" <<'EOF'
#!/bin/bash
exit 0
EOF

  if [ "$claude_probe" = "present" ]; then
    cat > "$home_dir/.local/bin/claude" <<'EOF'
#!/bin/bash
echo "Claude Code fake binary"
EOF

    cat > "$home_dir/.local/bin/sh" <<EOF
#!/bin/bash
if [ "\${1:-}" = "-lc" ] && [ "\${2:-}" = "command -v claude" ]; then
  echo "$home_dir/.local/bin/claude"
  exit 0
fi
exec /bin/sh "\$@"
EOF
  else
    cat > "$home_dir/.local/bin/sh" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "-lc" ] && [ "${2:-}" = "command -v claude" ]; then
  exit 1
fi
exec /bin/sh "$@"
EOF
  fi

  chmod +x "$fakebin/sudo" "$fakebin/curl" "$fakebin/rg" "$home_dir/.local/bin/sh"
  if [ "$claude_probe" = "present" ]; then
    chmod +x "$home_dir/.local/bin/claude"
  fi
}

run_doctor_capture() {
  local tmp="$1"
  local out="$2"
  set +e
  PATH="$tmp/fakebin:/usr/bin:/bin" \
    BAUDBOT_HOME="$tmp/home" \
    BAUDBOT_AGENT_USER="$(id -un)" \
    SUDO_USER="$(id -un)" \
    bash "$DOCTOR_SCRIPT" >"$out" 2>&1
  local rc=$?
  set -e
  [ "$rc" -ge 0 ]
}

test_reports_claude_when_available() {
  (
    set -euo pipefail
    local tmp out
    tmp="$(mktemp -d /tmp/baudbot-doctor-test.XXXXXX)"
    out="$(mktemp /tmp/baudbot-doctor-out.XXXXXX)"
    trap 'rm -rf "$tmp"; rm -f "$out"' EXIT

    mkdir -p "$tmp/home"
    make_fake_commands "$tmp/fakebin" "$tmp/home" "present"
    run_doctor_capture "$tmp" "$out"

    grep -q "rg is installed ($tmp/fakebin/rg)" "$out"
    grep -q "claude code is installed ($tmp/home/.local/bin/claude)" "$out"
  )
}

test_warns_when_claude_missing() {
  (
    set -euo pipefail
    local tmp out
    tmp="$(mktemp -d /tmp/baudbot-doctor-test.XXXXXX)"
    out="$(mktemp /tmp/baudbot-doctor-out.XXXXXX)"
    trap 'rm -rf "$tmp"; rm -f "$out"' EXIT

    mkdir -p "$tmp/home"
    make_fake_commands "$tmp/fakebin" "$tmp/home" "missing"
    run_doctor_capture "$tmp" "$out"

    grep -q "rg is installed ($tmp/fakebin/rg)" "$out"
    grep -q "claude code not found for" "$out"
  )
}

echo "=== doctor cli tests ==="
echo ""

run_test "reports Claude when available" test_reports_claude_when_available
run_test "warns when Claude is missing" test_warns_when_claude_missing

echo ""
echo "=== $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
