#!/bin/bash
# Shared helpers for setup.sh

bb_install_exec_wrapper() {
  local wrapper_path="$1"
  local target_exec="$2"

  if [ -z "$wrapper_path" ] || [ -z "$target_exec" ]; then
    echo "bb_install_exec_wrapper: wrapper path and target executable are required" >&2
    return 1
  fi

  if [ ! -x "$target_exec" ]; then
    echo "bb_install_exec_wrapper: target executable not found: $target_exec" >&2
    return 1
  fi

  local wrapper_dir tmp
  wrapper_dir="$(dirname "$wrapper_path")"
  mkdir -p "$wrapper_dir"

  tmp="$(mktemp "${wrapper_path}.tmp.XXXXXX")"
  printf '#!/bin/sh\nexec %q "$@"\n' "$target_exec" > "$tmp"
  chmod 755 "$tmp"

  if [ "$(id -u)" -eq 0 ]; then
    chown root:root "$tmp"
  fi

  rm -f "$wrapper_path"
  mv "$tmp" "$wrapper_path"
}
