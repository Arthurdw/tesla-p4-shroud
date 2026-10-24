"""Slice images + summary.txt for a CFD run (run scripts/cfd.sh first).

Usage: scripts/cfd_post.sh [run-name]   (wraps: uv run --python 3.12 --with pyvista python scripts/cfd_post.py)

Card coordinates as in cad/params.scad (mm): X = flow axis, Y = card thickness, Z = card height.
Comparative only: sealed-duct model, porous fins calibrated on a resolved unit cell, assumed fan curve, no heat transfer.
"""
import json
import math
import pathlib
import re
import sys
import numpy as np
import pyvista as pv

ROOT = pathlib.Path(__file__).resolve().parent.parent
RUN = sys.argv[1] if len(sys.argv) > 1 else "baseline"
OUT = ROOT / "output" / "cfd" / RUN
CASE = OUT / "case"
SIZE = (1600, 900)
EDGE = "#1b2b33"

RHO, NU = 1.2, 1.6e-5
CFM = 1 / 4.71947e-4
CP = 1006.0   # J/(kg K), air


def last(name):
    f = CASE / "postProcessing" / name / "0" / "surfaceFieldValue.dat"
    rows = [l.split() for l in f.read_text().splitlines() if l.strip() and not l.startswith("#")]
    # mean of the last 300 iterations: the porous/swirl solution wobbles by about +-0.5 % at the end of the run
    return sum(float(r[1]) for r in rows[-300:]) / len(rows[-300:])


def params():
    txt = (OUT / "cfd_params.txt").read_text().replace('"', "")
    v = {k: float(x) for k, x in re.findall(r"(\w+)=(\S+)", txt)}
    return v


def stats_on_slice(vol, x_mm):
    s = vol.slice(normal=(1, 0, 0), origin=(x_mm * 1e-3, 0, 0))
    return s


def shot(pl, name):
    pl.screenshot(OUT / name)
    pl.close()
    print(f"ok  {OUT.relative_to(ROOT)}/{name}")


def field_image(vol, name, title, normal, origin, view_dir, up, clim, box=None):
    s = vol.slice(normal=normal, origin=origin)
    if box is not None:
        s = s.clip_box(box, invert=False)
    pl = pv.Plotter(off_screen=True, window_size=SIZE)
    pl.enable_anti_aliasing("ssaa")
    pl.set_background("#f7f9fb", top="#d9e2ea")
    pl.add_mesh(s, scalars="magU", cmap="viridis", clim=clim, show_edges=False,
                scalar_bar_args=dict(title="|U| m/s (porous zone: superficial)", color=EDGE, vertical=False,
                                     position_x=0.3, position_y=0.04, width=0.4))
    t = pl.add_text(title, position="upper_left", font_size=12, color=EDGE)
    t.prop.background_color, t.prop.background_opacity = "#f7f9fb", 0.85
    pl.add_axes(line_width=3, color=EDGE)
    pl.view_vector(view_dir, viewup=up)
    pl.reset_camera()
    shot(pl, name)


def main():
    v = params()
    vtu = sorted((CASE / "VTK").glob("*/internal.vtu"))
    if not vtu:
        sys.exit(f"no VTK output in {CASE}/VTK; run scripts/cfd.sh {RUN} first")
    vol = pv.read(vtu[-1])
    vol.points = vol.points * 1000.0                  # m -> mm, card coordinates
    vol["magU"] = np.linalg.norm(vol["U"], axis=1) if "U" in vol.point_data else np.linalg.norm(vol.cell_data["U"], axis=1)
    if "U" in vol.point_data:
        vol.point_data["magU"] = np.linalg.norm(vol.point_data["U"], axis=1)
    vmax = float(np.percentile(vol.point_data["magU"], 99.5))
    clim = (0, vmax)
    cz, cy = v["chan_cz"], v["chan_cy"]

    field_image(vol, "cfd_fin_entry.png", f"{RUN}: |U| at fin entry (x = -1 mm), looking toward the fan",
                (1, 0, 0), (-1, 0, 0), (1, 0, 0), (0, 0, 1), clim)
    field_image(vol, "cfd_plane_z.png", f"{RUN}: |U| on z = {cz:.1f} mm (through the channel centre; the fan is at the left of the picture, +X points left)",
                (0, 0, 1), (0, 0, cz), (0, 0, -1), (0, 1, 0), clim)
    field_image(vol, "cfd_plane_y.png", f"{RUN}: |U| on y = {cy:.1f} mm (channel mid-plane)",
                (0, 1, 0), (0, cy, 0), (0, -1, 0), (0, 0, 1), clim)
    field_image(vol, "cfd_funnel_zfan.png", f"{RUN}: |U| on the fan-centre plane z = {v['fan_cz']:.1f} mm",
                (0, 0, 1), (0, 0, v["fan_cz"]), (0, 0, -1), (0, 1, 0), clim)

    q_in, q_out = abs(last("flow")), abs(last("flowOut"))
    p_in = abs(last("pInlet")) * RHO                  # kinematic -> Pa (static, fan face)
    p_entry = last("finEntry") * RHO
    p_exit = last("finExit") * RHO
    dp_fins = p_entry - p_exit
    # fin-entry plane x = -1 mm: flux and distribution over the fin channel only (y below the channel top)
    ybase, ytop = v["chan_cy"] - v["chan_h"] / 2, v["chan_cy"] + v["chan_h"] / 2
    sl = vol.slice(normal=(1, 0, 0), origin=(-1.0, 0, 0)).compute_cell_sizes(length=False, volume=False)
    ctr = sl.cell_centers().points
    A = sl.cell_data["Area"]; ux = np.abs(sl.cell_data["U"][:, 0])
    inch = ctr[:, 1] < ytop
    q_fins = float(np.sum(ux[inch] * A[inch])) * 1e-6          # mm2 * m/s -> m3/s
    near = ctr[:, 1] < ybase + 0.25 * v["chan_h"]
    near_frac = float(np.sum(ux[inch & near] * A[inch & near]) / np.sum(ux[inch] * A[inch]))
    um = np.sum(ux[inch] * A[inch]) / np.sum(A[inch])
    cov = float(np.sqrt(np.sum(A[inch] * (ux[inch] - um) ** 2) / np.sum(A[inch])) / um)
    # z distribution of the flux over the 10 fin-gap bands is not resolved by the porous model; report z-CoV on 10 bands instead
    zc = ctr[:, 2]; z0, z1 = v["chan_cz"] - v["chan_hz"] / 2, v["chan_cz"] + v["chan_hz"] / 2
    bands = np.clip(((zc - z0) / (z1 - z0) * 10).astype(int), 0, 9)
    qb = np.array([np.sum((ux * A)[inch & (bands == i)]) for i in range(10)])
    cov_z = float(qb.std() / qb.mean())
    # pressure along the duct (area-weighted, cell data) for the plot
    xs, ps = [], []
    for x in np.arange(-168.0, v["xend"] + 4.0, 2.0):
        t = vol.slice(normal=(1, 0, 0), origin=(x, 0, 0))
        if t.n_cells == 0: continue
        t = t.compute_cell_sizes(length=False, volume=False)
        xs.append(x); ps.append(float(np.sum(t.cell_data["p"] * t.cell_data["Area"]) / np.sum(t.cell_data["Area"]) * RHO))
    np.savetxt(OUT / "pressure_along_x.csv", np.c_[xs, ps], delimiter=",", header="x_mm,p_static_Pa_area_avg_over_cross_section", comments="")
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(9, 4.5), dpi=130)
    ax.plot(xs, ps, color="#1f77b4", lw=2)
    ax.axvspan(-v["hs_len"], 0, color="#cccccc", alpha=0.5, label="fin block (porous model)")
    ax.axvline(v["xs"], color="#888", ls=":"); ax.axvline(v["xf"], color="#888", ls=":")
    ax.text(v["xs"], max(ps) * 0.02, " end of straight\n channel", fontsize=8, color="#555")
    ax.text(v["xf"], max(ps) * 0.02, " end of funnel", fontsize=8, color="#555")
    ax.set_xlabel("x [mm]  (flow goes from the fan, right, toward the card, left)"); ax.set_ylabel("static pressure, cross-section average [Pa]")
    ax.set_title(f"{RUN}: pressure along the duct (comparative CFD, not a cooling validation)", fontsize=10)
    ax.legend(loc="upper left"); ax.grid(alpha=0.3); fig.tight_layout(); fig.savefig(OUT / "cfd_pressure_x.png"); plt.close(fig)
    print(f"ok  {OUT.relative_to(ROOT)}/cfd_pressure_x.png")

    log = (OUT / "log" / "solver.log").read_text()
    conv = re.search(r"SIMPLE solution converged in (\d+) iterations", log)
    lastit = re.findall(r"^Time = (\d+)", log, re.M)[-1]
    chk = (OUT / "log" / "checkMesh.log").read_text()
    cells = re.search(r"cells:\s+(\d+)", chk).group(1)
    nonorth = re.search(r"Mesh non-orthogonality Max: ([\d.]+)", chk).group(1)
    model = (OUT / "model.txt").read_text().splitlines()
    dT = lambda P_, q: P_ / (RHO * CP * q)
    res = dict(run=RUN, cells=int(cells), converged=bool(conv), iterations=int(conv.group(1)) if conv else int(lastit),
               q_in_m3s=q_in, q_in_cfm=q_in * CFM, q_fins_m3s=q_fins, q_fins_cfm=q_fins * CFM, mismatch_pct=abs(q_in - q_out) / max(q_in, q_out) * 100,
               dp_fan_Pa=p_in, dp_fins_Pa=dp_fins, dp_outside_Pa=p_in - dp_fins, cov_entry=cov, cov_entry_z_bands=cov_z, near_base_frac=near_frac,
               p_fin_exit_Pa=p_exit, p_fin_entry_Pa=p_entry, dyn_head_fin_exit_Pa=0.5 * RHO * (q_fins / (v['chan_h'] * v['chan_hz'] * 1e-6)) ** 2, dT50_K=dT(50, q_fins), dT75_K=dT(75, q_fins), model=model, fin_t=v["fin_t"])
    (OUT / "results.json").write_text(json.dumps(res, indent=1))
    lines = [
        f"CFD run '{RUN}'  (COMPARATIVE ONLY: assumed fan curve, porous fins calibrated on a resolved unit cell, no heat transfer, NOT a cooling validation)"] + model + [
        f"fin_pitch {v['fin_pitch']:.2f} mm (10 fins counted), fin_t {v['fin_t']:g} mm (assumed), fan_stack {int(v['fan_stack'])}",
        f"mesh: {cells} cells, max non-orthogonality {nonorth} deg; solver: " + (f"converged in {conv.group(1)} iterations" if conv else f"NOT converged to residualControl, stopped at iteration {lastit}"),
        f"inlet/outlet flow mismatch {res['mismatch_pct']:.3f} %",
        "",
        f"Q total (fan)            {q_in:.3e} m3/s = {q_in * CFM:.2f} CFM",
        f"Q through the fins       {q_fins:.3e} m3/s = {q_fins * CFM:.2f} CFM",
        f"fan-face static p        {p_in:.1f} Pa;  across the fins {dp_fins:.1f} Pa;  everything else {p_in - dp_fins:.1f} Pa",
        f"fin-entry CoV of |Ux|    {cov:.3f} (over y,z);  {cov_z:.3f} (over 10 z bands)",
        f"flow in the fin-base quarter (first {0.25 * v['chan_h']:.0f} mm above the block's solid base, y {ybase:.0f} to {ybase + 0.25 * v['chan_h']:.0f} mm) {near_frac * 100:.1f} % (uniform = 25 %)",
        f"air temperature rise     {dT(50, q_fins):.1f} K at 50 W, {dT(75, q_fins):.1f} K at 75 W (dT = P/(rho cp Q), rho 1.2, cp 1006, all heat into the fin flow)",
    ]
    (OUT / "summary.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


main()
