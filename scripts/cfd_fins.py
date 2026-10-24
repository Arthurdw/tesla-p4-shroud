#!/usr/bin/env python3
"""Resolved fin unit cell (one gap + half a fin each side, symmetry planes) in OpenFOAM, for scripts/cfd.sh.

What it does
  * meshes ONE fin gap with real solid walls: base plate at y=0, cover at y=chan_h (both no-slip), fin walls of
    thickness fin_t (blunt leading and trailing edge, wake region behind), 28 cells across the gap graded toward
    every wall (first cell ~0.07 mm, y+ ~ 1), 44 cells over the height, ~1 mm to 0.3 mm cells along the 170 mm;
  * runs simpleFoam laminar and kOmegaSST over several gap velocities and fin thicknesses;
  * writes output/cfd/fins/results.csv (total dp and developed-region friction) and cfd/fins/calibration.json,
    the dp = A*u_gap + B*u_gap^2 fits that scripts/cfd.sh turns into the Darcy-Forchheimer coefficients of the full model.

Usage: scripts/cfd_fins.py [--t 0.3 0.8] [--model laminar kOmegaSST] [--u 0.4 3 5 7 9] [--refine 1.0] [--tag NAME] [--keep NAME]
Needs Docker (opencfd/openfoam-default:2512). Comparative; no heat transfer. Dimensions come from cad/params.scad
(fin_pitch 5.16 mm, chan_h 8 mm, hs_len 170 mm).
"""
import argparse, csv, json, pathlib, re, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parent.parent
IMAGE = "opencfd/openfoam-default:2512"
RHO, NU = 1.2, 1.6e-5
P = dict(pitch=51.6 / 10, H=8.0, L=170.0, Lu=10.0, Ld=15.0)   # mm, from cad/params.scad


def params_from_scad():
    txt = (ROOT / "cad" / "params.scad").read_text()
    def num(name):
        m = re.search(rf"^{name}\s*=\s*([0-9.]+)\s*;", txt, re.M)
        return float(m.group(1)) if m else None
    P["H"] = num("hs_h") or P["H"]
    P["L"] = num("hs_len") or P["L"]
    hz, n = num("chan_hz"), num("fin_n")
    if hz and n:
        P["pitch"] = hz / n


def block_mesh(t, refine):
    p, H, L, Lu, Ld = P["pitch"], P["H"], P["L"], P["Lu"], P["Ld"]
    g = p - t
    xs = [-Lu, 0.0, L, L + Ld]
    zs = [0.0, g / 2, p / 2]
    ys = [0.0, H]
    r = refine
    nx = [round(12 * r), round(190 * r), round(14 * r)]      # upstream, fins, downstream
    nzg, nzf, ny = round(28 / 2 * r), max(3, round(t / 2 / 0.05)), round(44 * r)
    ny += ny % 2
    verts, vid = [], {}
    for yi, y in enumerate(ys):
        for zi, z in enumerate(zs):
            for xi, x in enumerate(xs):
                vid[(xi, yi, zi)] = len(verts)
                verts.append((x, y, z))
    def v(xi, yi, zi): return vid[(xi, yi, zi)]
    gy = "((0.5 0.5 4) (0.5 0.5 0.25))"
    blocks = []      # (xi, zi) -> block
    def hexv(xi, zi):
        return [v(xi, 0, zi), v(xi + 1, 0, zi), v(xi + 1, 1, zi), v(xi, 1, zi),
                v(xi, 0, zi + 1), v(xi + 1, 0, zi + 1), v(xi + 1, 1, zi + 1), v(xi, 1, zi + 1)]
    gx = {0: 0.25, 1: 8.0, 2: 3.0}
    out, inlet, outlet, sym, symf = [], [], [], [], []
    for xi in range(3):
        for zi in range(2):
            if xi == 1 and zi == 1:
                continue            # solid fin
            hv = hexv(xi, zi)
            ncz = nzg if zi == 0 else nzf
            gz = 0.2 if zi == 0 else 1
            out.append(f"hex ({' '.join(map(str, hv))}) ({nx[xi]} {ny} {ncz}) simpleGrading ({gx[xi]} {gy} {gz})")
            if xi == 0: inlet.append((hv[0], hv[4], hv[7], hv[3]))
            if xi == 2: outlet.append((hv[1], hv[2], hv[6], hv[5]))
            if zi == 0: sym.append((hv[0], hv[3], hv[2], hv[1]))
            else: symf.append((hv[4], hv[5], hv[6], hv[7]))
    f = lambda L_: " ".join("(" + " ".join(map(str, q)) + ")" for q in L_)
    text = "FoamFile { version 2.0; format ascii; class dictionary; object blockMeshDict; }\nscale 0.001;\n"
    text += "vertices (" + " ".join(f"({x} {y} {z})" for x, y, z in verts) + ");\n"
    text += "blocks (\n  " + "\n  ".join(out) + "\n);\nedges ();\n"
    text += f"boundary (\n inlet {{ type patch; faces ({f(inlet)}); }}\n outlet {{ type patch; faces ({f(outlet)}); }}\n"
    # z = 0 is the gap centre line and z = pitch/2 the fin centre line (upstream and wake): both symmetry planes
    text += f" symG {{ type symmetryPlane; faces ({f(sym)}); }}\n symF {{ type symmetryPlane; faces ({f(symf)}); }}\n);\n"
    text += "defaultPatch { name walls; type wall; }\n"
    return text, g


def foam_case(case, t, model, u, refine, endtime):
    p = P["pitch"]; g = p - t
    U = u * g / p                          # superficial velocity upstream of the fins
    d = case; (d / "0").mkdir(parents=True, exist_ok=True); (d / "constant").mkdir(exist_ok=True); (d / "system").mkdir(exist_ok=True)
    bm, _ = block_mesh(t, refine)
    (d / "system/blockMeshDict").write_text(bm)
    hdr = lambda c, o: f"FoamFile {{ version 2.0; format ascii; class {c}; object {o}; }}\n"
    (d / "constant/transportProperties").write_text(hdr("dictionary", "transportProperties") + f"transportModel Newtonian; nu {NU};\n")
    turb = model != "laminar"
    (d / "constant/turbulenceProperties").write_text(hdr("dictionary", "turbulenceProperties") +
        ("simulationType RAS; RAS { model kOmegaSST; turbulence on; printCoeffs off; }\n" if turb else "simulationType laminar;\n"))
    dh = 2 * g * P["H"] / (g + P["H"]) / 1000
    k_in = 1.5 * (0.05 * U) ** 2; om_in = (k_in ** 0.5) / (0.5477 * 0.07 * dh)
    def field(cls, name, dims, inlet, outlet, wall, internal, sym="symmetryPlane"):
        return (hdr(cls, name) + f"dimensions {dims};\ninternalField {internal};\nboundaryField\n{{\n"
                f"  inlet {{ {inlet} }}\n  outlet {{ {outlet} }}\n  walls {{ {wall} }}\n  symG {{ type {sym}; }}\n  symF {{ type {sym}; }}\n}}\n")
    (d / "0/U").write_text(field("volVectorField", "U", "[0 1 -1 0 0 0 0]", f"type fixedValue; value uniform ({U} 0 0);",
        "type inletOutlet; inletValue uniform (0 0 0); value uniform (0 0 0);", "type noSlip;", f"uniform ({U} 0 0)"))
    (d / "0/p").write_text(field("volScalarField", "p", "[0 2 -2 0 0 0 0]", "type zeroGradient;", "type fixedValue; value uniform 0;",
        "type zeroGradient;", "uniform 0"))
    if turb:
        (d / "0/k").write_text(field("volScalarField", "k", "[0 2 -2 0 0 0 0]", f"type fixedValue; value uniform {k_in};",
            "type inletOutlet; inletValue uniform 1e-6; value uniform 1e-6;", "type kqRWallFunction; value uniform 1e-6;", f"uniform {k_in}"))
        (d / "0/omega").write_text(field("volScalarField", "omega", "[0 0 -1 0 0 0 0]", f"type fixedValue; value uniform {om_in};",
            "type inletOutlet; inletValue uniform 100; value uniform 100;", f"type omegaWallFunction; value uniform {om_in};", f"uniform {om_in}"))
        (d / "0/nut").write_text(field("volScalarField", "nut", "[0 2 -1 0 0 0 0]", "type calculated; value uniform 0;",
            "type calculated; value uniform 0;", "type nutLowReWallFunction; value uniform 0;", "uniform 0"))
    plane = lambda name, x: (f"  {name} {{ type surfaceFieldValue; libs (fieldFunctionObjects); writeFields no; log no; writeControl timeStep; writeInterval 20;\n"
        f"    regionType sampledSurface; name {name}; sampledSurfaceDict {{ type cuttingPlane; planeType pointAndNormal; pointAndNormalDict {{ point ({x*1e-3} 0 0); normal (1 0 0); }} interpolate true; }}\n"
        f"    operation areaAverage; fields (p U); }}\n")
    (d / "system/controlDict").write_text(hdr("dictionary", "controlDict") +
        f"application simpleFoam; startFrom startTime; startTime 0; stopAt endTime; endTime {endtime}; deltaT 1;\n"
        "writeControl timeStep; writeInterval 100000; purgeWrite 1; writeFormat binary; runTimeModifiable no;\n"
        "functions\n{\n"
        "  pIn { type surfaceFieldValue; libs (fieldFunctionObjects); writeFields no; log no; writeControl timeStep; writeInterval 20; regionType patch; name inlet; operation areaAverage; fields (p); }\n"
        + plane("pA", 60) + plane("pB", 160) + "}\n")
    (d / "system/fvSchemes").write_text(hdr("dictionary", "fvSchemes") +
        "ddtSchemes { default steadyState; }\ngradSchemes { default Gauss linear; }\n"
        "divSchemes { default none; div(phi,U) bounded Gauss linearUpwind grad(U); div(phi,k) bounded Gauss upwind; div(phi,omega) bounded Gauss upwind;\n"
        "  div((nuEff*dev2(T(grad(U))))) Gauss linear; }\n"
        "laplacianSchemes { default Gauss linear corrected; }\ninterpolationSchemes { default linear; }\nsnGradSchemes { default corrected; }\nwallDist { method meshWave; }\n")
    (d / "system/fvSolution").write_text(hdr("dictionary", "fvSolution") +
        "solvers { p { solver GAMG; smoother GaussSeidel; tolerance 1e-9; relTol 0.01; } \"(U|k|omega)\" { solver smoothSolver; smoother symGaussSeidel; tolerance 1e-9; relTol 0.1; } }\n"
        "SIMPLE { consistent yes; nNonOrthogonalCorrectors 0; residualControl { p 1e-6; U 1e-7; k 1e-7; omega 1e-7; } }\n"
        "relaxationFactors { equations { U 0.9; \".*\" 0.9; } }\n")


def run_case(args):
    name, t, model, u, refine, endtime, keep, base = args
    case = base / name
    shutil.rmtree(case, ignore_errors=True)
    foam_case(case, t, model, u, refine, endtime)
    cmd = "blockMesh > log.mesh 2>&1 && checkMesh > log.check 2>&1 && simpleFoam > log.solver 2>&1"
    r = subprocess.run(["docker", "run", "--rm", "-u", f"{__import__('os').getuid()}:{__import__('os').getgid()}", "-v", f"{case}:/case", "-w", "/case",
                        IMAGE, "-c", f"cd /case && {cmd}"], capture_output=True, text=True)
    def last(fn):
        f = case / "postProcessing" / fn / "0" / "surfaceFieldValue.dat"
        rows = [l.split() for l in f.read_text().splitlines() if l.strip() and not l.startswith("#")]
        return rows[-1]
    try:
        solver = (case / "log.solver").read_text()
        check = (case / "log.check").read_text()
        assert "Mesh OK" in check, "checkMesh failed"
        assert "nan" not in solver.lower().replace("nan(", "x"), "NaN"
        conv = re.search(r"SIMPLE solution converged in (\d+)", solver)
        its = int(conv.group(1)) if conv else int(re.findall(r"^Time = (\d+)", solver, re.M)[-1])
        p_in = float(last("pIn")[1]) * RHO
        pa, pb = float(last("pA")[1]) * RHO, float(last("pB")[1]) * RHO
        cells = int(re.search(r"cells:\s+(\d+)", check).group(1))
        res = dict(name=name, t=t, model=model, u_gap=u, dp_total=p_in, dpdx=(pa - pb) / 0.1, iters=its, converged=bool(conv), cells=cells)
    except Exception as e:       # report, keep the log
        print(f"FAILED {name}: {e}\n{r.stdout[-300:]}{r.stderr[-300:]}", file=sys.stderr)
        return dict(name=name, failed=True)
    if name not in keep:
        for sub in ("processor0", "0", "constant", "system", "postProcessing"):
            shutil.rmtree(case / sub, ignore_errors=True)
        for tdir in case.glob("[1-9]*"):
            shutil.rmtree(tdir, ignore_errors=True)
    print(f"done {name}: dp {p_in:.1f} Pa  iters {its}  conv {bool(conv)}  cells {cells}", flush=True)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--t", type=float, nargs="+", default=[0.3, 0.8])
    ap.add_argument("--model", nargs="+", default=["laminar", "kOmegaSST"])
    ap.add_argument("--u", type=float, nargs="+", default=[0.4, 3, 5, 7, 9])
    ap.add_argument("--refine", type=float, default=1.0)
    ap.add_argument("--tag", default="")
    ap.add_argument("--endtime", type=int, default=4000)
    ap.add_argument("--keep", nargs="*", default=[], help="case names whose files (incl. VTK) are kept")
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--fit-only", action="store_true", help="skip the runs, refit from output/cfd/fins/results.csv")
    ap.add_argument("--no-calibration", action="store_true")
    a = ap.parse_args()
    params_from_scad()
    base = ROOT / "output" / "cfd" / "fins"
    base.mkdir(parents=True, exist_ok=True)
    jobs = [(f"t{t:g}_{m}_u{u:g}{a.tag}", t, m, u, a.refine, a.endtime, a.keep, base)
            for t in a.t for m in a.model for u in a.u]
    if a.fit_only:
        res = [dict(r, t=float(r["t"]), u_gap=float(r["u_gap"]), dp_total=float(r["dp_total"])) for r in csv.DictReader(open(base / f"results{a.tag}.csv"))]
    else:
        with ThreadPoolExecutor(a.jobs) as ex:
            res = list(ex.map(run_case, jobs))
    ok = [r for r in res if not r.get("failed")]
    if len(ok) != len(res):
        sys.exit("FAILED: some unit-cell cases failed")
    fn = base / f"results{a.tag}.csv"
    if not a.fit_only:
        with open(fn, "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=list(ok[0].keys())); w.writeheader(); w.writerows(ok)
        print("wrote", fn.relative_to(ROOT))
    if a.no_calibration or a.tag:
        return
    # dp = A u + B u^2 over u >= 3 m/s (the working range), per (t, model); u is the gap velocity
    import numpy as np
    cal = {"_note": "unit-cell fits, total dp over upstream channel + 170 mm of fins + wake + outlet; dp[Pa] = A*u + B*u^2, u = gap-mean velocity [m/s]",
           "pitch_mm": P["pitch"], "H_mm": P["H"], "L_mm": P["L"]}
    for t in a.t:
        for m in a.model:
            rows = [r for r in ok if r["t"] == t and r["model"] == m and r["u_gap"] >= 3]
            if len(rows) < 3: continue
            u = np.array([r["u_gap"] for r in rows]); dp = np.array([r["dp_total"] for r in rows])
            A, B = np.linalg.lstsq(np.c_[u, u * u], dp, rcond=None)[0]
            cal[f"t{t:g}_{m}"] = dict(A=float(A), B=float(B), max_resid_pct=float(np.max(np.abs(A * u + B * u * u - dp) / dp) * 100))
    (ROOT / "cfd" / "fins" / "calibration.json").write_text(json.dumps(cal, indent=1))
    print(json.dumps(cal, indent=1))


if __name__ == "__main__":
    main()
