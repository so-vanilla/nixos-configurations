#!/usr/bin/env sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

HOOK_SOURCE="$SCRIPT_DIR/git-hooks/pre-commit"
HOOK_DEST="$SCRIPT_DIR/.git/hooks/pre-commit"

# コピーと実行権限の付与
cp "$HOOK_SOURCE" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
