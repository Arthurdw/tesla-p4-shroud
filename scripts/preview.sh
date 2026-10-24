#!/usr/bin/env bash
# Render output/preview_*.png from the exported STLs (run scripts/export.sh first). Needs uv.
set -euo pipefail
cd "$(dirname "$0")/.."
exec uv run -q --python 3.12 --with pyvista python scripts/preview.py "$@"
