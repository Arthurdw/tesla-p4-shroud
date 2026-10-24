#!/usr/bin/env bash
# Comparative CFD of the shroud air path (OpenFOAM porousSimpleFoam in Docker). NOT a cooling validation.
# Fan and card never enter cad/ outputs; the CFD-only air volume is cfd/domain.scad.
# Usage: scripts/cfd.sh [--run NAME] [--fan ippc|noctua] [--curve stall|linear] [--rpm N] [--cal laminar|kOmegaSST|analytic]
#          [--swirl on|off] [--swirl-dir 1|-1] [--leak MM2] [--bypass MM] [--cell MM] [--procs N] [--endtime N] [--surf "MIN MAX"] [--box-level N] [-D name=value ...]
#   default: Noctua NF-F12 iPPC-3000 (assumed stall-shaped P/Q curve from cfd/fans/), 3000 rpm, fins from the resolved unit-cell
#   calibration (cfd/fins/calibration.json, scripts/cfd_fins.py), fan-hub blockage and an assumed exit swirl.
#   e.g. scripts/cfd.sh --run novanes -D vanes_y=0 -D vanes_z=0     --fan noctua : NF-P12 redux-1700, linear curve, as before
# Output: output/cfd/<run>/{case,summary.txt,*.png}. Exits non-zero on any step error, failed checkMesh,
# NaN, or inlet/outlet flow mismatch above 1 %.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
IMAGE=opencfd/openfoam-default:2512
swirldir=1
run=baseline fan=ippc curve=stall rpm=3000 cal=laminar swirl=on leak=0 bypass=0 cell=4.0 procs=6 endtime=3000 surf="1 2" boxlevel=2 featlevel=2
defs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run) run=$2; shift 2;;
    --fan) fan=$2; shift 2;;
    --curve) curve=$2; shift 2;;
    --rpm) rpm=$2; shift 2;;
    --cal) cal=$2; shift 2;;
    --swirl) swirl=$2; shift 2;;
    --swirl-dir) swirldir=$2; shift 2;;   # +1: fan spins +X (default); -1: opposite. ASSUMED, the real rotation direction is not known
    --leak) leak=$2; shift 2;;
    --bypass) bypass=$2; shift 2;;
    --cell) cell=$2; shift 2;;
    --procs) procs=$2; shift 2;;
    --endtime) endtime=$2; shift 2;;
    --surf) surf=$2; shift 2;;
    --box-level) boxlevel=$2; shift 2;;
    -D) defs+=(-D "$2"); shift 2;;
    -D*) defs+=(-D "${1#-D}"); shift;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done
out="$ROOT/output/cfd/$run"
case_dir="$out/case"
rm -rf "$out"; mkdir -p "$case_dir/constant/triSurface"
cp -r cfd/case/. "$case_dir/"
log="$out/log"; mkdir -p "$log"

step() { echo "== $1"; }
of() { # run an OpenFOAM command line in the case; log to $log/<name>.log
  local name=$1; shift
  step "$name"
  docker run --rm -u "$(id -u):$(id -g)" -v "$case_dir:/case" -w /case "$IMAGE" -c "cd /case && $*" >"$log/$name.log" 2>&1 \
    || { tail -30 "$log/$name.log"; echo "FAILED: $name (see $log/$name.log)" >&2; exit 1; }
}

defs+=(-D "leak_a=$leak" -D "bypass_h=$bypass")
# 1. CAD -> STL (mm), plus the CFD parameters echoed by cfd/domain.scad
step "openscad"
olog=$(openscad "${defs[@]}" -D 'part="none"' -o "$case_dir/constant/triSurface/shroud_mm.stl" cfd/domain.scad 2>&1) \
  || { echo "$olog"; echo "FAILED: openscad" >&2; exit 1; }
grep -qE "ERROR|Assertion" <<<"$olog" && { echo "$olog"; echo "FAILED: openscad" >&2; exit 1; }
grep -qiE "empty" <<<"$olog" && { echo "FAILED: empty CFD geometry" >&2; exit 1; }
echo "$olog" | grep 'ECHO: "CFD ' > "$out/cfd_params.txt" || { echo "FAILED: no CFD echo" >&2; exit 1; }

# 2. fill the placeholders
python3 - "$out/cfd_params.txt" "$case_dir" "$procs" "$endtime" "$surf" "$boxlevel" "$featlevel" "$fan" "$curve" "$rpm" "$cal" "$cell" <<'PY'
import re, sys, pathlib
txt, case, procs, endtime, surf, boxlevel, featlevel, fan, curve, rpm, cal, cell = sys.argv[1:]
import json, csv
rpm = float(rpm); cell = float(cell)
kv = dict(re.findall(r'(\w+)=(\S+)', open(txt).read().replace('"', '')))
v = {k: float(x) for k, x in kv.items()}
m = 1e-3
bx0, bx1 = -v['hs_len'] - v.get('diff_ext', 0), v['xend'] + 3
by0, by1, bz0, bz1 = v['ymin'], v['ymax'], v['zmin'], v['zmax']
# Fan curve. iPPC: tabulated shape from cfd/fans/nf-f12-ippc-3000.csv (shape ASSUMED, only pmax 74.8 Pa and Qmax 186.7 m3/h are
# published), fan laws Q ~ n, dp ~ n^2 for --rpm, series fans add pressure. NF-P12: two-point linear (as before).
rho = 1.2
if fan == 'noctua':
    pts = [(0.0, 27.75), (70.75 * 4.71947e-4, 0.0)]
    desc = 'NF-P12 redux-1700 linear 27.75 Pa / 70.75 CFM (assumed linear)'
elif fan == 'ippc':
    pmax, qmax = 74.8 * (rpm/3000)**2, 186.7 / 3600 * (rpm/3000)
    rows = [r for r in csv.DictReader(l for l in open('cfd/fans/nf-f12-ippc-3000.csv') if not l.startswith('#'))]
    col = {'stall': 'p_frac_stall', 'linear': 'p_frac_linear'}[curve]
    pts = [(float(r['q_frac']) * qmax, float(r[col]) * pmax) for r in rows]
    desc = f'NF-F12 iPPC-3000 at {rpm:g} rpm, {curve} curve (shape assumed; pmax {pmax:.1f} Pa, Qmax {qmax*3600:.1f} m3/h)'
else: sys.exit('unknown --fan ' + fan)
pts = [(q, p * v['fan_stack']) for q, p in pts]
fan_table = '\n'.join(f'    ({q:.8g} {p/rho:.8g})' for q, p in pts)
fan_pa, fan_q = pts[0][1], pts[-1][0]
# Fin porous coefficients: from the resolved unit cell (cfd/fins/calibration.json): dp = A u_gap + B u_gap^2 -> d = A/(mu L phi), f = 2B/(rho L phi^2)
d_use, f_use, calsrc = v['d'], v['f'], 'analytic (Shah & London fRe + fin_k)'
if cal != 'analytic':
    c = json.load(open('cfd/fins/calibration.json'))
    t = v['fin_t']; ts = sorted(float(k[1:].split('_')[0]) for k in c if k.startswith('t') and k.endswith('_' + cal))
    if abs(c['pitch_mm'] - v['fin_pitch']) > 0.02 * v['fin_pitch']: sys.exit('calibration pitch differs from fin_pitch: rerun scripts/cfd_fins.py')
    if ts and ts[0] - 1e-9 <= t <= ts[-1] + 1e-9:
        lo = max(x for x in ts if x <= t + 1e-9); hi = min(x for x in ts if x >= t - 1e-9)
        w = 0 if hi == lo else (t - lo) / (hi - lo)
        g = lambda x, k: c[f't{x:g}_{cal}'][k]
        A = (1-w) * g(lo, 'A') + w * g(hi, 'A'); B = (1-w) * g(lo, 'B') + w * g(hi, 'B')
        phi = (v['fin_pitch'] - t) / v['fin_pitch']; L = v['hs_len'] / 1000
        d_use = A / (1.92e-5 * L * phi); f_use = 2 * B / (rho * L * phi**2)
        calsrc = f'unit cell {cal}, A {A:.3f} B {B:.4f} (fin_t {t:g}, interpolated {lo:g}..{hi:g})'
    else: print(f'WARNING: no {cal} calibration for fin_t {t:g}; using the analytic porous coefficients', file=sys.stderr)
print('fan:', desc); print('fins:', calsrc, f'd {d_use:.4g} f {f_use:.4g}')
open(f'{case}/../model.txt', 'w').write(f'fan: {desc}\nfins: {calsrc}\nd={d_use} f={f_use}\nswirl_rpm={rpm}\ncell={cell} leak_a={v["leak_a"]} bypass_h={v["bypass_h"]} hub_d={v["hub_d"]}\n')
fan_dp = fan_pa / rho
s0, s1 = surf.split()
sub = {
 'BXMIN': bx0, 'BXMAX': bx1, 'BYMIN': by0, 'BYMAX': by1, 'BZMIN': bz0, 'BZMAX': bz1,
 'NX': round((bx1-bx0)/cell), 'NY': round((by1-by0)/cell), 'NZ': round((bz1-bz0)/cell),
 'RXMIN': (bx0-2)*m, 'RXMAX': (v['xs']+5)*m,
 'RYMIN': (v['chan_cy']-v['chan_h']/2-1)*m, 'RYMAX': (v['chan_cy']+v['chan_h']/2+1)*m,
 'RZMIN': (v['chan_cz']-v['chan_hz']/2-1)*m, 'RZMAX': (v['chan_cz']+v['chan_hz']/2+1)*m,
 'LOCX': v['loc_x']*m + 0.00013, 'LOCY': v['loc_y']*m + 0.00011, 'LOCZ': v['loc_z']*m + 0.00007,
 'SURFMIN': s0, 'SURFMAX': s1, 'BOXLEVEL': boxlevel, 'FEATLEVEL': featlevel,
 'FXMIN': -v['hs_len']*m, 'FXMAX': 0.0, 'FEX': -0.001, 'FOX': -v['hs_len']*m + 0.0005,
 'ENDTIME': endtime, 'NPROC': procs,
 'DD': d_use, 'FF': f_use, 'FANTABLE': fan_table,
 'FYMAX': (v['chan_cy'] + v['chan_h']/2) * m + 1e-4,
 'FYMIN': (v['chan_cy'] - v['chan_h']/2) * m - 1e-4,
}
for p in pathlib.Path(case).rglob('*'):
    if p.is_file() and 'triSurface' not in p.parts:
        t = p.read_text()
        for k, x in sub.items():
            t = t.replace(f'@{k}@', f'{x:.8g}' if isinstance(x, float) else str(x))
        if '@' in re.sub(r'/\*.*?\*/', '', t):
            left = set(re.findall(r'@\w+@', re.sub(r'/\*.*?\*/', '', t)))
            if left: sys.exit(f'unfilled placeholders in {p}: {left}')
        p.write_text(t)
open(f'{case}/../hand_params.txt', 'w').write(
    f"fan_p0={fan_pa} fan_qmax={fan_q} rpm={rpm} fin_k={v['fin_k']} fin_dh={v['fin_dh']} fin_fre={v['fin_fre']} fin_pitch={v['fin_pitch']} fin_t={v['fin_t']} hs_len={v['hs_len']} fan_stack={int(v['fan_stack'])} chan_h={v['chan_h']} chan_hz={v['chan_hz']}\n")
print(f"cells in background mesh: {sub['NX']*sub['NY']*sub['NZ']}")
PY

# 3. mesh
of scale "surfaceTransformPoints -scale '(0.001 0.001 0.001)' constant/triSurface/shroud_mm.stl constant/triSurface/shroud.stl"
rm -f "$case_dir/constant/triSurface/shroud_mm.stl"
of blockMesh "blockMesh"
of surfaceFeatureExtract "surfaceFeatureExtract"
of snappyHexMesh "snappyHexMesh -overwrite"
of checkMesh "checkMesh"
if ! grep -q "Mesh OK" "$log/checkMesh.log"; then tail -30 "$log/checkMesh.log"; echo "FAILED: checkMesh" >&2; exit 1; fi
of topoSet "topoSet"
nfin=$(grep -oE 'cellZoneSet fins.*' "$log/topoSet.log" | head -1 || true)
grep -E "cells|Cell" "$log/topoSet.log" | tail -3 || true

# 3b. exit swirl at the fan face (ASSUMED, off with --swirl off): solid-body tangential velocity at the inlet faces,
# magnitude from Euler work c_theta,m = 0.9 pmax / (rho Omega r_m eta_h) with eta_h 0.7, r_m 0.04 m, so it scales with rpm.
if [[ "$swirl" == on && "$fan" == ippc ]]; then
  of cellCentres "postProcess -func writeCellCentres -time 0"
  python3 - "$case_dir" "$out/cfd_params.txt" "$rpm" "$swirldir" <<'PY'
import re, sys, math
case, txt, rpm, sdir = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
v = {k: float(x) for k, x in re.findall(r'(\w+)=(\S+)', open(txt).read().replace('"', ''))}
C = open(f'{case}/0/C').read()
m = re.search(r'inlet\s*\{[^}]*?value\s+nonuniform List<vector>\s*(\d+)\s*\((.*?)\n\)\s*;', C, re.S)
n = int(m.group(1)); pts = re.findall(r'\(([-\d.e+ ]+)\)', m.group(2)); assert len(pts) == n
omega = rpm * math.pi / 30; rm = 0.04
cth = 0.9 * 74.8 * (rpm/3000)**2 / (1.2 * omega * rm * 0.7); k = sdir * cth / rm
cy, cz = v['fan_cy'] * 1e-3, v['fan_cz'] * 1e-3
vec = []
for p in pts:
    x, y, z = map(float, p.split())
    vec.append(f'(0 {-k*(z-cz):.5g} {k*(y-cy):.5g})')
U = open(f'{case}/0/U').read()
U = U.replace('inlet  { type pressureInletOutletVelocity; value uniform (0 0 0); }',
  f'inlet  {{ type pressureInletOutletVelocity; value uniform (0 0 0); tangentialVelocity nonuniform List<vector> {n} ( ' + ' '.join(vec) + ' ); }')
assert 'tangentialVelocity' in U
open(f'{case}/0/U', 'w').write(U)
print(f'swirl: c_theta at r_m {cth:.2f} m/s ({n} inlet faces)')
PY
fi

# 4. solve
rm -rf "$case_dir"/processor*
of decomposePar "decomposePar -force"
of solver "mpirun -np $procs porousSimpleFoam -parallel"
of reconstructPar "reconstructPar -latestTime"
of foamToVTK "foamToVTK -latestTime -fields '(U p)' -ascii"
rm -rf "$case_dir"/processor*

# 5. checks
if grep -qiE '(^|[^a-z])-?nan([^a-z]|$)' "$log/solver.log"; then echo "FAILED: NaN in the solver log" >&2; exit 1; fi
if grep -q "FOAM FATAL\|FOAM exiting" "$log/solver.log"; then echo "FAILED: solver error" >&2; exit 1; fi
last() { grep -v '^#' "$case_dir/postProcessing/$1/0/surfaceFieldValue.dat" | tail -1 | awk '{print $2}'; }
qin=$(last flow); qout=$(last flowOut)
python3 - "$qin" "$qout" <<'PY'
import sys
a, b = abs(float(sys.argv[1])), abs(float(sys.argv[2]))
err = abs(a-b)/max(a, b, 1e-30)
print(f"inlet Q {a:.4e} m3/s, outlet Q {b:.4e} m3/s, mismatch {err*100:.3f} %")
if err > 0.01: sys.exit("FAILED: inlet/outlet flow mismatch above 1 %")
PY
grep -E "SIMPLE solution converged" "$log/solver.log" || echo "WARNING: not converged to residualControl within $endtime iterations"
echo "ok  $case_dir (post-process: scripts/cfd_post.sh $run)"
