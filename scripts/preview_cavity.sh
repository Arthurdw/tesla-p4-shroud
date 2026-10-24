#!/usr/bin/env bash
# Render output/preview_cavity.png (sleeve cavity section + card outline). Run scripts/export.sh first. Needs uv.
set -euo pipefail
cd "$(dirname "$0")/.."
exec uv run -q --python 3.12 --with pyvista --with matplotlib python scripts/preview_cavity.py
