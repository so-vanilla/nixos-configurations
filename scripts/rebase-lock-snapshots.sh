#!/usr/bin/env bash
set -euo pipefail

# lock snapshot branchをmain HEADベースで再構築する
# flake.lockだけ各branchの既存のものを維持し、それ以外はmainに追従させる

SNAPSHOTS=(
  "lock/1-day-ago:lock snapshot: 1 day ago"
  "lock/2-days-ago:lock snapshot: 2 days ago"
)

git fetch origin

MAIN_REF=$(git rev-parse origin/main)
MAIN_LOCK=$(git rev-parse origin/main:flake.lock)
MAIN_TREE_LINES=$(git ls-tree origin/main)

echo "main: $MAIN_REF"

for entry in "${SNAPSHOTS[@]}"; do
  BRANCH="${entry%%:*}"
  MESSAGE="${entry#*:}"

  if ! git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    echo "skip: origin/$BRANCH does not exist"
    continue
  fi

  OLD_LOCK=$(git rev-parse "origin/$BRANCH:flake.lock")

  if [ "$OLD_LOCK" = "$MAIN_LOCK" ]; then
    echo "skip: $BRANCH (flake.lock is identical to main)"
    continue
  fi

  CURRENT_PARENT=$(git rev-parse "origin/$BRANCH^")
  if [ "$CURRENT_PARENT" = "$MAIN_REF" ]; then
    echo "skip: $BRANCH (already based on main HEAD)"
    continue
  fi

  TREE=$(echo "$MAIN_TREE_LINES" \
    | awk -v old="$MAIN_LOCK" -v new="$OLD_LOCK" \
        '$4 == "flake.lock" { sub(old, new) } { print }' \
    | git mktree)

  COMMIT=$(git commit-tree "$TREE" -m "$MESSAGE" -p "$MAIN_REF")
  git push -f origin "$COMMIT:refs/heads/$BRANCH"

  echo "done: $BRANCH -> $COMMIT (parent: $MAIN_REF)"
done
