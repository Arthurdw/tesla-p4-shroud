#!/usr/bin/env bash
# Slice images and summary.txt for a CFD run. Usage: scripts/cfd_post.sh [run-name]  (needs uv)
set -euo pipefail
cd "$(dirname "$0")/.."
exec uv run -q --python 3.12 --with pyvista --with matplotlib python scripts/cfd_post.py "$@"
