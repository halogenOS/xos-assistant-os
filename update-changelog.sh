#!/usr/bin/env bash
# Regenerate assistant-changelog.txt from the assistant repository's history
# between two of its revisions — the bot embeds the result at build time and
# serves it through its changelog tool, so the file must be regenerated in
# the same commit that moves the assistant-src pin.
#
# Usage: update-changelog.sh <checkout> <old-rev> <new-rev>
#   checkout  a local clone of the assistant repository holding both revs
#   old-rev   the pin the previous deployment ran
#   new-rev   the pin this deployment moves to
set -euo pipefail

checkout=$1
old=$2
new=$3
out="$(dirname "$0")/assistant-changelog.txt"

{
  echo "Changes from ${old:0:12} to ${new:0:12}:"
  echo
  git -C "$checkout" log --reverse --date=format:'%Y-%m-%d %H:%M' \
    --format='%ad  %s%n%n%b---' "$old..$new"
} > "$out"

echo "wrote $out ($(wc -l < "$out") lines)"
