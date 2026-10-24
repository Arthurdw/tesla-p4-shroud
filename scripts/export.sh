#!/usr/bin/env bash
# Export all STLs. Exits non-zero on any CAD error, empty output, or interference.
# Usage: scripts/export.sh [--release]
set -euo pipefail
cd "$(dirname "$0")/.."
extra=()
[[ "${1:-}" == "--release" ]] && extra=(-D release=true)
mkdir -p output
rm -f output/shroud_spacer.stl   # old preview-only build, now the default shroud
# 3MF (OpenSCAD 2021.01 writes it) for the slicer-ready print parts, in addition to STL.
# The default build is the spacer stack (the fan flange is a separate print: shroud with a lug flange + key groove, spacer, fan).
# The optional stator layer, its nose puck and the key ring mate with that same shroud. The stator layer adds stator_layer_t to the
# stack, which no longer fits stack_max_len, so its parts are built with the limit lifted (stack_max_len=999): it is optional.
layer_cfg=(-D stator_layer=true -D stack_max_len=999)
for p in sleeve sleeve_print shroud shroud_print spacer spacer_print stator_layer stator_layer_print stator_nose seal_ring \
         fitcheck_mouth fitcheck_interface fitcheck_fanface support_clip support_leg support_foot snap_comb support_assy; do
  case "$p" in sleeve_print|shroud_print|spacer_print|stator_layer_print|fitcheck_mouth) fmts="stl 3mf";; *) fmts="stl";; esac
  pargs=(); part="$p"
  case "$p" in stator_layer|stator_layer_print|stator_nose) pargs=("${layer_cfg[@]}");; esac
  for f in $fmts; do
  out="output/$p.$f"
  rm -f "$out"
  log=$(openscad "${extra[@]}" "${pargs[@]}" -D "part=\"$part\"" -o "$out" cad/shroud.scad 2>&1) || { echo "$log"; echo "FAILED: $p" >&2; exit 1; }
  grep -qE "ERROR|Assertion" <<<"$log" && { echo "$log"; echo "FAILED: $p" >&2; exit 1; }
  grep -qiE "empty" <<<"$log" && { echo "FAILED: $p exported empty geometry" >&2; exit 1; }
  [[ -s "$out" ]] || { echo "FAILED: $p produced no file" >&2; exit 1; }
  echo "ok  $out"
  done
done
# Fan-face coupons for the flare diameter, marked with 1 / 2 / 3 index holes (a real 137 mm flare needs a deeper bellmouth and
# a 14 mm spacer, the thinnest that keeps the inserts and the key groove clear of that bellmouth, see README). Same asserts as the main parts.
for v in "127 1 12 spacer 12" "132 2 12 spacer 12" "137 3 13 spacer 14"; do
  read -r d m dep mod spt <<<"$v"
  out="output/fitcheck_fanface_d$d.stl"
  rm -f "$out"
  log=$(openscad "${extra[@]}" -D 'part="fitcheck_fanface"' -D "fan_flare_d=$d" -D "fitcheck_mark=$m" -D "flare_depth=$dep" -D "stack_module=\"$mod\"" -D "spacer_t=$spt" -D stack_max_len=999 -D plenum_len=14 -o "$out" cad/shroud.scad 2>&1) || { echo "$log"; echo "FAILED: $out" >&2; exit 1; }
  grep -qE "ERROR|Assertion" <<<"$log" && { echo "$log"; echo "FAILED: $out" >&2; exit 1; }
  [[ -s "$out" ]] || { echo "FAILED: $out produced no file" >&2; exit 1; }
  echo "ok  $out"
done
# Interference: must be EMPTY (OpenSCAD reports an empty top-level object). Checked without and with the stator layer fitted
# (the layer moves the fan face out by stator_layer_t, and its asserts only run when it is fitted).
tmp=$(mktemp --suffix=.stl); trap 'rm -f "$tmp"' EXIT
for sl in false true; do
  if [[ $sl == true ]]; then
    # The stator layer adds stator_layer_t to the stack (148 + 3 mm), over stack_max_len: it is optional and off by default, so it is
    # built with the limit lifted and a problem here is reported as a WARNING, not a failure.
    sargs=(-D stack_max_len=999)
  else
    sargs=()
  fi
  log=$(openscad "${extra[@]}" "${sargs[@]}" -D 'part="interference"' -D "stator_layer=$sl" -o "$tmp" cad/shroud.scad 2>&1 || true)
  if grep -qE "ERROR|Assertion" <<<"$log"; then
    echo "$log"
    if [[ $sl == true ]]; then echo "WARNING: optional stator-layer configuration does not build (stator_layer=true)" >&2; continue; fi
    echo "FAILED: interference build (stator_layer=$sl)" >&2; exit 1
  fi
  if ! grep -qi "empty" <<<"$log"; then
    if [[ $sl == true ]]; then echo "WARNING: optional stator-layer configuration (spacer + layer) collides with a keep-out: it does not fit the case" >&2; continue; fi
    echo "FAILED: shroud collides with the card, fan envelope or a keep-out, stator_layer=$sl (see: -D 'part=\"interference\"')" >&2; exit 1
  fi
  echo "ok  no interference with configured keep-outs (stator_layer=$sl)"
done
# Air path: must also be EMPTY. Catches printed solid left inside the duct (a wall across the channel, a boss breaking in),
# which the keep-out check cannot see because it only looks outward.
log=$(openscad "${extra[@]}" -D 'part="airpath"' -o "$tmp" cad/shroud.scad 2>&1 || true)
if grep -qE "ERROR|Assertion" <<<"$log"; then echo "$log"; echo "FAILED: airpath build" >&2; exit 1; fi
if ! grep -qi "empty" <<<"$log"; then
  echo "FAILED: printed solid inside the air path (see: -D 'part=\"airpath\"')" >&2; exit 1
fi
echo "ok  air path open (no printed solid within airpath_margin of the duct)"
echo "NOTE: geometry only. Cooling is NOT validated; check nvidia-smi temps under load."
