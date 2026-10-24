#!/usr/bin/env bash
# Run several cfd.sh cases, N at a time, then post-process each.
# Usage: scripts/cfd_batch.sh JOBS "name|cfd.sh args" ["name|args" ...]
set -uo pipefail
cd "$(dirname "$0")/.."
jobs=$1; shift
run_one() { name=${1%%|*}; args=${1#*|}; scripts/cfd.sh --run "$name" $args > "/tmp/cfd_$name.log" 2>&1 && scripts/cfd_post.sh "$name" > "/tmp/cfd_post_$name.log" 2>&1; echo "finished $name rc=$?"; }
export -f run_one
printf '%s\0' "$@" | xargs -0 -P "$jobs" -I{} bash -c 'run_one "$1"' _ {}
