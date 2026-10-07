#!/usr/bin/env bash
set -euo pipefail

# Replace the nested lock blob while preserving every other entry in REF.
ref=${1:?Usage: lock-snapshot-tree.sh REF LOCK_BLOB}
lock_blob=${2:?Usage: lock-snapshot-tree.sh REF LOCK_BLOB}
old_lock=$(git rev-parse "$ref:nixos-configuration/flake.lock")
old_config=$(git rev-parse "$ref:nixos-configuration")
new_config=$(git ls-tree "$old_config" |
  awk -v old="$old_lock" -v new="$lock_blob" '$4 == "flake.lock" { sub(old, new) } { print }' |
  git mktree)
git ls-tree "$ref" |
  awk -v old="$old_config" -v new="$new_config" '$4 == "nixos-configuration" { sub(old, new) } { print }' |
  git mktree
