#!/bin/bash
# Tests for bin/lib/setup-common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=bin/lib/setup-common.sh
source "$SCRIPT_DIR/setup-common.sh"

TOTAL=0
PASSED=0
FAILED=0

run_test() {
  local name="$1"
  shift
  local out

  TOTAL=$((TOTAL + 1))
  printf "  %-45s " "$name"

  out="$(mktemp /tmp/baudbot-setup-common-test-output.XXXXXX)"
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

test_install_exec_wrapper_creates_executable() {
  (
    set -euo pipefail
    local tmp target wrapper output
    tmp="$(mktemp -d /tmp/baudbot-setup-common-test.XXXXXX)"
    trap 'rm -rf "$tmp"' EXIT

    target="$tmp/bin/target"
    mkdir -p "$(dirname "$target")"
    cat >"$target" <<'EOF'
#!/bin/sh
echo "target:$*"
EOF
    chmod +x "$target"

    wrapper="$tmp/usr/local/bin/claude"
    bb_install_exec_wrapper "$wrapper" "$target"

    [ -x "$wrapper" ]
    output="$("$wrapper" --version)"
    [ "$output" = "target:--version" ]
  )
}

test_install_exec_wrapper_replaces_symlink_without_touching_target() {
  (
    set -euo pipefail
    local tmp target wrapper output
    tmp="$(mktemp -d /tmp/baudbot-setup-common-test.XXXXXX)"
    trap 'rm -rf "$tmp"' EXIT

    target="$tmp/target-bin"
    cat >"$target" <<'EOF'
#!/bin/sh
echo "target:$*"
EOF
    chmod +x "$target"

    wrapper="$tmp/usr/local/bin/claude"
    mkdir -p "$(dirname "$wrapper")"
    ln -s "$target" "$wrapper"

    bb_install_exec_wrapper "$wrapper" "$target"

    [ ! -L "$wrapper" ]
    output="$("$wrapper" ok)"
    [ "$output" = "target:ok" ]
    # Ensure target content itself wasn't replaced via symlink-following writes.
    grep -q 'target:\$*' "$target"
  )
}

test_install_exec_wrapper_fails_when_target_missing() {
  (
    set -euo pipefail
    local tmp wrapper
    tmp="$(mktemp -d /tmp/baudbot-setup-common-test.XXXXXX)"
    trap 'rm -rf "$tmp"' EXIT
    wrapper="$tmp/usr/local/bin/claude"

    if bb_install_exec_wrapper "$wrapper" "$tmp/missing-target"; then
      return 1
    fi
  )
}

echo "=== setup-common tests ==="
echo ""

run_test "install wrapper creates executable launcher" test_install_exec_wrapper_creates_executable
run_test "install wrapper replaces symlink safely" test_install_exec_wrapper_replaces_symlink_without_touching_target
run_test "install wrapper fails when target missing" test_install_exec_wrapper_fails_when_target_missing

echo ""
echo "=== $PASSED/$TOTAL passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
